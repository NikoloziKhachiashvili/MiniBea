#import "Tweak.h"

%hook PAGDeviceHelper
+ (BOOL)bu_isJailBroken {
	return NO;
}
%end

%hook STKDevice
+ (BOOL)containsJailbrokenFiles {
	return NO;
}

+ (BOOL)containsJailbrokenPermissions {
	return NO;
}

+ (BOOL)isJailbroken {
	return NO;
}
%end

%hook HomeViewController
- (void)viewDidLoad {
	%orig;

	UIStackView *stackView = (UIStackView *)[[self ibNavBarLogoImageView] superview];
	stackView.axis = UILayoutConstraintAxisHorizontal;
	stackView.alignment = UIStackViewAlignmentCenter;
	
	UIImageView *plusImage = [[UIImageView alloc] init];
	plusImage.image = [UIImage systemImageNamed:@"plus.app"];
	plusImage.translatesAutoresizingMaskIntoConstraints = NO;

	[stackView addArrangedSubview:plusImage];

	UITapGestureRecognizer *tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
	[stackView addGestureRecognizer:tapGestureRecognizer];
	[stackView setUserInteractionEnabled:YES];
}

%new
- (void)handleTap:(UITapGestureRecognizer *)gestureRecognizer {
	if (![[BeaTokenManager sharedInstance] BRAccessToken]) return;

	BeaUploadViewController *beaUploadViewController = [[BeaUploadViewController alloc] init];
	beaUploadViewController.modalPresentationStyle = UIModalPresentationFullScreen;
	[self presentViewController:beaUploadViewController animated:YES completion:nil];
}
%end

%hook NSMutableURLRequest
-(void)setAllHTTPHeaderFields:(NSDictionary *)arg1 {
	%orig;

	if ([[arg1 allKeys] containsObject:@"Authorization"] && [[arg1 allKeys] containsObject:@"bereal-device-id"] && !headers) {
		if ([arg1[@"Authorization"] length] > 0) {
			headers = (NSDictionary *)arg1;
			[[BeaTokenManager sharedInstance] setHeaders:headers];
		}
	} 
}
%end

%hook CAFilter
-(void)setValue:(id)arg1 forKey:(id)arg2 {
    // remove the blur that gets applied to the BeReals
	// this is kind of a fallback if the normal unblur function somehow fails (BeReal 2.0+)

	if (([arg1 isEqual:@(13)] || [arg1 isEqual:@(8)]) && [self.name isEqual:@"gaussianBlur"]) {
		return %orig(0, arg2);
	}
    %orig;
}
%end

// Device introspection (objc_getClassList scanning every loaded class) proved
// there is no plain "UIHostingController" class to resolve at all: BeReal's
// screens are all concrete bound-generic specializations like
// _TtGC7SwiftUI19UIHostingControllerV6BeReal10ReportView_ - Swift mints a
// distinct runtime class per SwiftUI view type, one per screen, with no
// shared name to hook. But every one of those specializations reports its
// own superclass as plain UIViewController, and UIViewController is already
// hooked here (for the alert-dismissal fix below) - so the button logic lives
// on viewDidLayoutSubviews here instead of on any one hosting-controller
// class. The >=400pt width filter in qualifyingImageViewsInView: is what
// keeps this scoped to actual BeReal photos rather than firing on every
// screen in the app (settings, profile, camera, etc. all reach this too).
%hook UIViewController
%property (nonatomic, strong) BeaButton *downloadButton;
%property (nonatomic, strong) UIView *downloadButtonAnchor;

- (void)presentViewController:(UIViewController *)viewControllerToPresent animated:(BOOL)flag completion:(void (^)(void))completion {
	// BeReal somehow shows an error alert when using this tweak (at least on my device), so remove it
    if ([viewControllerToPresent isKindOfClass:[UIAlertController class]]) {
        UIAlertController *alert = (UIAlertController *)viewControllerToPresent;
        if ([alert.message isEqualToString:@"[\"Unable to load contents\"]"]) {
            return;
        }
    }
    %orig;
}

- (void)viewDidLayoutSubviews {
	%orig;

	UIView *root = [self view];
	if (!root) return;

	// Content can get replaced/rebuilt under a given controller (e.g. cell/
	// controller reuse, or navigating to different content). If the image
	// view we last anchored to is no longer part of this controller's view,
	// tear down and re-attach against what's showing now.
	if ([self downloadButton] && (![self downloadButtonAnchor] || ![[self downloadButtonAnchor] isDescendantOfView:root])) {
		[[self downloadButton] removeFromSuperview];
		[self setDownloadButton:nil];
		[self setDownloadButtonAnchor:nil];
	}

	if ([self downloadButton]) return;

	UIView *anchor = [BeaDownloader qualifyingImageViewsInView:root].firstObject;
	if (!anchor) return;

	BeaButton *downloadButton = [BeaButton downloadButton];
	downloadButton.layer.zPosition = 99;

	[self setDownloadButton:downloadButton];
	[self setDownloadButtonAnchor:anchor];
	[root addSubview:downloadButton];

	[NSLayoutConstraint activateConstraints:@[
		[[downloadButton trailingAnchor] constraintEqualToAnchor:anchor.trailingAnchor constant:-11.6],
		[[downloadButton topAnchor] constraintEqualToAnchor:anchor.topAnchor constant:11.6]
	]];
}
%end

BOOL isBlockedPath(const char *path) {
    if (!path) return NO;
    
    NSString *pathStr = @(path);
    
    if ([pathStr hasPrefix:@"/var/jb/"] || 
        [pathStr hasPrefix:@"/private/preboot/"] || 
        [pathStr hasPrefix:@"/private/var/jb"] ||
        [pathStr hasPrefix:@"/private/var/lib/apt"] ||
        [pathStr hasPrefix:@"/private/var/lib/cydia"] ||
        [pathStr hasPrefix:@"/private/var/stash"] ||
        [pathStr hasPrefix:@"/private/var/tmp/cydia"]) {
        return YES;
    }
    
    NSArray *jbPaths = @[
        @"/Applications/Cydia.app",
        @"/Library/MobileSubstrate/MobileSubstrate.dylib",
        @"/System/Library/LaunchDaemons/com.ikey.bbot.plist",
        @"/System/Library/LaunchDaemons/com.saurik.Cydia.Startup.plist",
        @"/bin/bash",
        @"/etc/apt",
        @"/usr/bin/sshd",
        @"/usr/libexec/sftp-server",
        @"/usr/sbin/sshd"
    ];

    for (NSString *jbPath in jbPaths) {
        if ([pathStr isEqualToString:jbPath]) {
            return YES;
        }
    }
    
    return NO;
}

%hook NSFileManager
- (BOOL)fileExistsAtPath:(NSString *)path {
    if (isBlockedPath([path UTF8String])) {
        return NO;
    }
    return %orig;
}
%end

%hook AdvertsDataNativeViewContainer
- (void)didMoveToSuperview {
    [self removeFromSuperview];
}

- (CGSize)sizeThatFits:(CGSize)size {
    return CGSizeZero;
}

- (CGSize)intrinsicContentSize {
    return CGSizeZero;
}
%end

%ctor {
	%init(
      HomeViewController = objc_getClass("BeReal.HomeViewController"),
	  AdvertsDataNativeViewContainer = objc_getClass("AdvertsData.AdvertNativeViewContainer")
	);
}