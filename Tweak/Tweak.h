#import <UIKit/UIKit.h>
#import "fishhook/fishhook.h"
#import "Utilities/Button/BeaButton.h"
#import "BeFake/TokenManager/BeaTokenManager.h"
#import "BeFake/ViewControllers/UploadViewController/BeaUploadViewController.h"

NSDictionary *headers;

@interface AdvertsDataNativeViewContainer : UIView
@end

@interface PAGDeviceHelper : NSObject
+ (BOOL)bu_isJailBroken;
@end

@interface STKDevice : NSObject
+ (BOOL)containsJailbrokenFiles;
+ (BOOL)containsJailbrokenPermissions;
+ (BOOL)isJailbroken;
@end

@interface HomeViewController : UIViewController
@property (nonatomic, retain) UIImageView *ibNavBarLogoImageView;
- (void)showVersionAlert;
@end

@interface CAFilter : NSObject
@property (copy) NSString *name;
@end

// As of BeReal 4.87.0 the main friends feed is a full-screen swipeable pager
// (FeedsUIPresentation/FeedsFeaturePresentation, PostPagerV2) with no plain
// UIKit cell class of its own - unlike the separate POV video feature
// (FeaturePOVPresentation.POVPostHostingCollectionViewCell), which does have
// one but turned out to be the wrong screen entirely (confirmed via device
// log: that hook's class resolved fine, but layoutSubviews never fired -
// the user was never on the POV screen). Rather than keep guessing at
// BeReal's private internal class names, hook Apple's own public
// UIHostingController instead: BeReal's binary references
// SwiftUI.UIHostingController's generic metadata directly, and unlike the
// deeply-private _UIHostingView specializations the original tweak targeted
// a year ago, this is documented, stable API. Swift's ObjC bridging for
// generic classes like this preserves the base class name across concrete
// specializations, so NSStringFromClass on any UIHostingController<T>
// instance reports back as plain "UIHostingController" regardless of T -
// this is the standard, well-established way tweaks hook SwiftUI-hosted
// content generically, without needing to know anything BeReal-specific.
@interface UIHostingController : UIViewController
@property (nonatomic, strong) BeaButton *downloadButton;
// Strongly held (not weak) so it's always safe to message even if BeReal's
// own code has since detached it from the hierarchy - see the staleness
// check in the %hook implementation.
@property (nonatomic, strong) UIView *downloadButtonAnchor;
@end