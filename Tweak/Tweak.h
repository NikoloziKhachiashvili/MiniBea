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

// As of BeReal 4.87.0 each feed post renders as a cell in a UICollectionView,
// with its content hosted from SwiftUI. Earlier versions of this tweak hooked
// the SwiftUI-private hosting view directly (by hardcoded mangled class name)
// to inject the download button, but that name belongs to Apple's own
// SwiftUI.framework internals and isn't stable across iOS versions - hooking
// this cell class instead (a real, BeReal-owned class) is far less likely to
// silently break on the next OS or app update.
@interface POVPostHostingCollectionViewCell : UICollectionViewCell
@property (nonatomic, strong) BeaButton *downloadButton;
// Strongly held (not weak) so it's always safe to message even if BeReal's
// own code has since detached it from the hierarchy - see the staleness
// check in the %hook implementation.
@property (nonatomic, strong) UIView *downloadButtonAnchor;
@end