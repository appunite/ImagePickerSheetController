//
//  ImagePickerController.swift
//  ImagePickerSheet
//
//  Created by Laurin Brandner on 24/05/15.
//  Copyright (c) 2015 Laurin Brandner. All rights reserved.
//

import Foundation
import Photos

private let previewCollectionViewInset: CGFloat = 5

/// The media type an instance of ImagePickerSheetController can display
@objc public enum ImagePickerMediaType : Int {
    case Image
    case Video
    case ImageAndVideo
    case None
}

@objc @available(iOS 8.0, *)
public class ImagePickerSheetController: UIViewController {
    
    var sheetCollectionView: UICollectionView {
        return sheetController.sheetCollectionView
    }
    
    lazy var backgroundView: UIView = {
        let view = UIView()
        view.accessibilityIdentifier = "ImagePickerSheetBackground"
        
        if !self.isPresentedAsPopover {
            view.backgroundColor = UIColor(white: 0.0, alpha: 0.3961)
        }
        
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: "cancel"))
        
        return view
    }()
    
    private lazy var sheetController: SheetController = {
        let controller = SheetController(previewCollectionView: self.previewCollectionView, displayPreview: self.mediaType != .None)
        controller.actionHandlingCallback = { [weak self] in
            self?.dismissViewControllerAnimated(true, completion: nil)
        }
        
        return controller
    }()
    
    private(set) lazy var previewCollectionView: PreviewCollectionView = {
        let collectionView = PreviewCollectionView()
        collectionView.accessibilityIdentifier = "ImagePickerSheetPreview"
        collectionView.backgroundColor = .clearColor()
        collectionView.allowsMultipleSelection = true
        collectionView.imagePreviewLayout.sectionInset = UIEdgeInsetsMake(previewCollectionViewInset, previewCollectionViewInset, previewCollectionViewInset, previewCollectionViewInset)
        collectionView.imagePreviewLayout.showsSupplementaryViews = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.alwaysBounceHorizontal = true
        collectionView.registerClass(PreviewCollectionViewCell.self, forCellWithReuseIdentifier: NSStringFromClass(PreviewCollectionViewCell.self))
        collectionView.registerClass(PreviewSupplementaryView.self, forSupplementaryViewOfKind: UICollectionElementKindSectionHeader, withReuseIdentifier: NSStringFromClass(PreviewSupplementaryView.self))
        
        return collectionView
    }()
    
    private var supplementaryViews = [Int: PreviewSupplementaryView]()
    
    private var selectedImageIndices = [Int]() {
        didSet {
            sheetController.numberOfSelectedImages = selectedImageIndices.count
        }
    }
    
    private var assets = [PHAsset]()
    
    private lazy var requestOptions: PHImageRequestOptions = {
        let options = PHImageRequestOptions()
        options.deliveryMode = .Opportunistic
        options.resizeMode = .Fast
        
        return options
    }()
    
    private lazy var imageManager: PHCachingImageManager? = {
    
        if self.mediaType == .None {
            return nil
        }
        
        return PHCachingImageManager();
    }()
    
    private let minimumPreviewHeight: CGFloat = 129
    private var maximumPreviewHeight: CGFloat = 129
    
    private var previewCheckmarkInset: CGFloat {
        guard #available(iOS 9, *) else {
            return 3.5
        }
        
        return 12.5
    }
    
    override public var modalPresentationStyle:UIModalPresentationStyle {
        didSet {
            if modalPresentationStyle == .Popover {
                backgroundView.backgroundColor = .clearColor()
            } else {
                backgroundView.backgroundColor = UIColor(white: 0.0, alpha: 0.3961)
            }
        }
    }
    
    private var isPresentedAsPopover:Bool {
        
        let style = self.popoverPresentationController?.presentationStyle
        return style == .Popover && modalPresentationStyle == .Popover
    }
    
    // MARK: - Public accessable variables
    
    /// Maximum number of images to display (larger amounts can slow down the result!
    public var imageLimit = 50
    
    /// Specify the preferred status bar style
    public var statusBarStyle:UIStatusBarStyle?
    
    /// All the actions. The first action is shown at the top.
    public var actions: [ImagePickerAction] {
        return sheetController.actions
    }
    
    /// If set to true, after taping on preview image it enlarges
    public var enableEnlargedPreviews: Bool = true;
    
    /// Maximum selection of images.
    public var maximumSelection: Int?
    
    /// The selected image assets
    public var selectedImageAssets: [PHAsset] {
        return selectedImageIndices.map { self.assets[$0] }
    }
    
    /// The media type of the displayed assets
    public let mediaType: ImagePickerMediaType
    
    /// Whether the image preview has been elarged. This is the case when at least once
    /// image has been selected.
    public private(set) var enlargedPreviews = false
    
    // MARK: - Initialization
    
    public init(mediaType: ImagePickerMediaType) {
        
        self.mediaType = mediaType
        super.init(nibName: nil, bundle: nil)
        initialize()
    }
    
    public required init?(coder aDecoder: NSCoder) {
        
        self.mediaType = .ImageAndVideo
        super.init(coder: aDecoder)
        initialize()
    }
    
    private func initialize() {
        
        modalPresentationStyle = .Custom
        transitioningDelegate = self
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "cancel", name: UIApplicationDidEnterBackgroundNotification, object: nil)
    }
    
    deinit {
        
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }
    
    // MARK: - View Lifecycle
    override public func loadView() {
        
        super.loadView()
        self.view.backgroundColor = .clearColor()
        view.addSubview(backgroundView)
        view.addSubview(sheetCollectionView)
    }
    
    public override func viewWillAppear(animated: Bool) {
        
        super.viewWillAppear(animated)
        
        if mediaType == .None {
//            previewCollectionView.removeFromSuperview()
            
        } else {
            preferredContentSize = CGSize(width: 400, height: view.frame.height)
            
            if PHPhotoLibrary.authorizationStatus() == .Authorized {
                prepareAssets()
            }
        }
    }
    
    public override func viewDidAppear(animated: Bool) {
        
        super.viewDidAppear(animated)
        
        if PHPhotoLibrary.authorizationStatus() == .NotDetermined {
            PHPhotoLibrary.requestAuthorization() { status in
                if status == .Authorized {
                    dispatch_async(dispatch_get_main_queue()) {
                        self.prepareAssets()
                        self.previewCollectionView.reloadData()
                        self.sheetCollectionView.reloadData()
                        self.view.setNeedsLayout()
                        
                        // Explicitely disable animations so it wouldn't animate either
                        // if it was in a popover
                        CATransaction.begin()
                        CATransaction.setDisableActions(true)
                        self.view.layoutIfNeeded()
                        CATransaction.commit()
                    }
                }
            }
        }
    }
    
    // MARK: - Actions
    
    /// Adds an new action.
    /// If the passed action is of type Cancel, any pre-existing Cancel actions will be removed.
    /// Always arranges the actions so that the Cancel action appears at the bottom.
    public func addAction(action: ImagePickerAction) {
        
        sheetController.addAction(action)
        view.setNeedsLayout()
    }
    
    @objc private func cancel() {
        
        sheetController.handleCancelAction()
    }
    
    // MARK: - Images
    
    private func sizeForAsset(asset: PHAsset, scale: CGFloat = 1) -> CGSize {
        
        let proportion = CGFloat(asset.pixelWidth)/CGFloat(asset.pixelHeight)
        
        let imageHeight = maximumPreviewHeight - 2 * previewCollectionViewInset
        let imageWidth = floor(proportion * imageHeight)
        
        return CGSize(width: imageWidth * scale, height: imageHeight * scale)
    }
    
    private func prepareAssets() {
        
        if mediaType == .None {
            return
        }
        
        fetchAssets()
        reloadMaximumPreviewHeight()
        reloadCurrentPreviewHeight(invalidateLayout: false)
        
        // Filter out the assets that are too thin. This can't be done before because
        // we don't know how tall the images should be
        let minImageWidth = 2 * previewCheckmarkInset + (PreviewSupplementaryView.checkmarkImage?.size.width ?? 0)
        assets = assets.filter { asset in
            let size = sizeForAsset(asset)
            return size.width >= minImageWidth
        }
    }
    
    private func fetchAssets() {
        
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        switch mediaType {
        case .Image:
            options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.Image.rawValue)
        case .Video:
            options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.Video.rawValue)
        case .ImageAndVideo:
            options.predicate = NSPredicate(format: "mediaType = %d OR mediaType = %d", PHAssetMediaType.Image.rawValue, PHAssetMediaType.Video.rawValue)
        case .None: return;
            
        }
        
        if #available(iOS 9, *) {
            options.fetchLimit = imageLimit
        }
        
        let result = PHAsset.fetchAssetsWithOptions(options)
        let amount = min(result.count, imageLimit)
        self.assets = result.objectsAtIndexes(NSIndexSet(indexesInRange: NSRange(location: 0, length: amount))) as? [PHAsset] ?? []
    }
    
    private func requestImageForAsset(asset: PHAsset, completion: (image: UIImage?, requestId:PHImageRequestID?) -> ()) -> PHImageRequestID {
        
        if let manager = self.imageManager  {
            let targetSize = sizeForAsset(asset, scale: UIScreen.mainScreen().scale)
            requestOptions.synchronous = false
            
            // Workaround because PHImageManager.requestImageForAsset doesn't work for burst images
            if asset.representsBurst {
                return manager.requestImageDataForAsset(asset, options: requestOptions) { data, _, _, dict in
                    let image = data.flatMap { UIImage(data: $0) }
                    let requestId = dict?[PHImageResultRequestIDKey] as? NSNumber
                    completion(image: image, requestId: requestId?.intValue)
                }
            }
            else {
                return manager.requestImageForAsset(asset, targetSize: targetSize, contentMode: .AspectFill, options: requestOptions) { image, dict in
                    let requestId = dict?[PHImageResultRequestIDKey] as? NSNumber
                    completion(image: image, requestId: requestId?.intValue)
                }
            }
        }
        
        return 0
    }
    
    private func prefetchImagesForAsset(asset: PHAsset) {
        if let manager = self.imageManager {
            let targetSize = sizeForAsset(asset, scale: UIScreen.mainScreen().scale)
            manager.startCachingImagesForAssets([asset], targetSize: targetSize, contentMode: .AspectFill, options: requestOptions)
        }
    }
    
    public func fetchURLForSelectedPhotos(completion: (urls: [NSURL]) -> ()) {
        
        let selectedAssets = self.selectedImageAssets
        
        var assetsURL : [NSURL] = []
        var count = 0
        
        for asset:PHAsset in selectedAssets {
            self.requestImageForAsset(asset, completion: { (image, requestId) -> () in
                if let imageURL : NSURL = self.saveImageOnDisk(image!) {
                    assetsURL.append(imageURL)
                    
                    count++;
                    if (self.selectedImageAssets.count == count){
                        completion(urls: assetsURL);
                    }
                }
            })
        }
        
    }
    
    
    private func saveImageOnDisk(image: UIImage) -> NSURL? {
        
        let nsDocumentDirectory = NSSearchPathDirectory.DocumentDirectory
        let nsUserDomainMask = NSSearchPathDomainMask.UserDomainMask
        let paths = NSSearchPathForDirectoriesInDomains(nsDocumentDirectory, nsUserDomainMask, true)
        
        if paths.count > 0 {
            
            let dirURL = NSURL(fileURLWithPath:paths[0])
            let writeURL = dirURL.URLByAppendingPathComponent(NSProcessInfo.processInfo().globallyUniqueString)
            
            UIImageJPEGRepresentation(image, 0.6)!.writeToURL(writeURL, atomically: true)
            
            return writeURL
        }
        
        return nil
    }
    
    
    // MARK: - Layout
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        backgroundView.frame = view.bounds
        
        reloadMaximumPreviewHeight()
        reloadCurrentPreviewHeight(invalidateLayout: true)
        
        let sheetHeight = sheetController.preferredSheetHeight
        let sheetSize = CGSize(width: view.bounds.width, height: sheetHeight)
        
        // This particular order is necessary so that the sheet is layed out
        // correctly with and without an enclosing popover
        preferredContentSize = sheetSize
        sheetCollectionView.frame = CGRect(origin: CGPoint(x: view.bounds.minX, y: view.bounds.maxY-sheetHeight), size: sheetSize)
    }
    
    private func reloadCurrentPreviewHeight(invalidateLayout invalidate: Bool) {
        if assets.count <= 0 {
            sheetController.setPreviewHeight(0, invalidateLayout: invalidate)
        }
        else if assets.count > 0 && enlargedPreviews {
            sheetController.setPreviewHeight(maximumPreviewHeight, invalidateLayout: invalidate)
        }
        else {
            sheetController.setPreviewHeight(minimumPreviewHeight, invalidateLayout: invalidate)
        }
    }
    
    private func reloadMaximumPreviewHeight() {
        let maxHeight: CGFloat = 400
        let maxImageWidth = sheetController.preferredSheetWidth - 2 * previewCollectionViewInset
        
        let assetRatios = assets.map { CGSize(width: max($0.pixelHeight, $0.pixelWidth), height: min($0.pixelHeight, $0.pixelWidth)) }
            .map { $0.height / $0.width }
        
        let assetHeights = assetRatios.map { $0 * maxImageWidth }
            .filter { $0 < maxImageWidth && $0 < maxHeight } // Make sure the preview isn't too high eg for squares
            .sort(>)
        let assetHeight = ceil(assetHeights.first ?? 0)
        
        // Just a sanity check, to make sure this doesn't exceed 400 points
        let scaledHeight = max(min(assetHeight, maxHeight), 200)
        maximumPreviewHeight = scaledHeight + 2 * previewCollectionViewInset
    }
    
    // MARK: -
    
    func enlargePreviewsByCenteringToIndexPath(indexPath: NSIndexPath?, completion: (Bool -> ())?) {
        enlargedPreviews = enableEnlargedPreviews
        
        previewCollectionView.imagePreviewLayout.invalidationCenteredIndexPath = indexPath
        reloadCurrentPreviewHeight(invalidateLayout: false)
        
        view.setNeedsLayout()
        
        let animationDuration: NSTimeInterval
        if #available(iOS 9, *) {
            animationDuration = 0.2
        }
        else {
            animationDuration = 0.3
        }
        
        UIView.animateWithDuration(animationDuration, animations: {
            self.sheetCollectionView.reloadSections(NSIndexSet(index: 0))
            self.view.layoutIfNeeded()
            }, completion: completion)
    }
    
    public override func preferredStatusBarStyle() -> UIStatusBarStyle {
        
        if let statusBarStyle = statusBarStyle {
            return statusBarStyle
        }
        return super.preferredStatusBarStyle()
    }
}

// MARK: - UICollectionViewDataSource

extension ImagePickerSheetController: UICollectionViewDataSource {
    
    public func numberOfSectionsInCollectionView(collectionView: UICollectionView) -> Int {
        return self.mediaType == .None ? 0 : assets.count
    }
    
    public func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return 1
    }
    
    public func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCellWithReuseIdentifier(NSStringFromClass(PreviewCollectionViewCell.self), forIndexPath: indexPath) as! PreviewCollectionViewCell
        
        if let imageManager = self.imageManager {
            let asset = assets[indexPath.section]
            if let id = cell.requestId {
                imageManager.cancelImageRequest(id)
                cell.requestId = nil
            }
            cell.videoIndicatorView.hidden = asset.mediaType != .Video
            
            cell.requestId = requestImageForAsset(asset) { image, requestId in
                if requestId == cell.requestId || cell.requestId == nil {
                    cell.imageView.image = image
                }
            }
            
            cell.selected = selectedImageIndices.contains(indexPath.section)
        }
    
        return cell
    }
    
    public func collectionView(collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, atIndexPath indexPath:
        NSIndexPath) -> UICollectionReusableView {
            
            let view = collectionView.dequeueReusableSupplementaryViewOfKind(UICollectionElementKindSectionHeader, withReuseIdentifier: NSStringFromClass(PreviewSupplementaryView.self), forIndexPath: indexPath) as! PreviewSupplementaryView
            view.userInteractionEnabled = false
            view.buttonInset = UIEdgeInsetsMake(0.0, previewCheckmarkInset, previewCheckmarkInset, 0.0)
            view.selected = selectedImageIndices.contains(indexPath.section)
            
            supplementaryViews[indexPath.section] = view
            
            return view
    }
    
}

// MARK: - UICollectionViewDelegate

extension ImagePickerSheetController: UICollectionViewDelegate {
    
    public func collectionView(collectionView: UICollectionView, didSelectItemAtIndexPath indexPath: NSIndexPath) {
        
        if let maximumSelection = maximumSelection {
            if selectedImageIndices.count >= maximumSelection, let previousItemIndex = selectedImageIndices.first {
                
                let previousItemIndexPath = NSIndexPath(forItem: 0, inSection: previousItemIndex)
                
                supplementaryViews[previousItemIndex]?.selected = false
                selectedImageIndices.removeAtIndex(0)
                collectionView.deselectItemAtIndexPath(previousItemIndexPath, animated: true)
            }
        }
        
        // Just to make sure the image is only selected once
        selectedImageIndices = selectedImageIndices.filter { $0 != indexPath.section }
        selectedImageIndices.append(indexPath.section)
        
        if !enlargedPreviews {
            enlargePreviewsByCenteringToIndexPath(indexPath) { _ in
                self.sheetController.reloadActionItems()
                self.previewCollectionView.imagePreviewLayout.showsSupplementaryViews = true
            }
        }
        else {
            // scrollToItemAtIndexPath doesn't work reliably
            if let cell = collectionView.cellForItemAtIndexPath(indexPath) {
                var contentOffset = CGPointMake(cell.frame.midX - collectionView.frame.width / 2.0, 0.0)
                contentOffset.x = max(contentOffset.x, -collectionView.contentInset.left)
                contentOffset.x = min(contentOffset.x, collectionView.contentSize.width - collectionView.frame.width + collectionView.contentInset.right)
                
                collectionView.setContentOffset(contentOffset, animated: true)
            }
            
            sheetController.reloadActionItems()
        }
        
        supplementaryViews[indexPath.section]?.selected = true
    }
    
    public func collectionView(collectionView: UICollectionView, didDeselectItemAtIndexPath indexPath: NSIndexPath) {
        if let index = selectedImageIndices.indexOf(indexPath.section) {
            selectedImageIndices.removeAtIndex(index)
            sheetController.reloadActionItems()
        }
        
        supplementaryViews[indexPath.section]?.selected = false
    }
    
}

// MARK: - UICollectionViewDelegateFlowLayout

extension ImagePickerSheetController: UICollectionViewDelegateFlowLayout {
    
    public func collectionView(collectionView: UICollectionView, layout: UICollectionViewLayout, sizeForItemAtIndexPath indexPath: NSIndexPath) -> CGSize {
        let asset = assets[indexPath.section]
        let size = sizeForAsset(asset)
        
        // Scale down to the current preview height, sizeForAsset returns the original size
        let currentImagePreviewHeight = sheetController.previewHeight - 2 * previewCollectionViewInset
        let scale = currentImagePreviewHeight / size.height
        
        return CGSize(width: size.width * scale, height: currentImagePreviewHeight)
    }
    
    public func collectionView(collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        let checkmarkWidth = PreviewSupplementaryView.checkmarkImage?.size.width ?? 0
        return CGSizeMake(checkmarkWidth + 2 * previewCheckmarkInset, sheetController.previewHeight - 2 * previewCollectionViewInset)
    }
    
}

// MARK: - UIViewControllerTransitioningDelegate

extension ImagePickerSheetController: UIViewControllerTransitioningDelegate {
    
    public func animationControllerForPresentedController(presented: UIViewController, presentingController presenting: UIViewController, sourceController source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return AnimationController(imagePickerSheetController: self, presenting: true)
    }
    
    public func animationControllerForDismissedController(dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return AnimationController(imagePickerSheetController: self, presenting: false)
    }
    
}
