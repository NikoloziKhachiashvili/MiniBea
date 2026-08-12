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

// TEMPORARY diagnostics - remove once the button reliably appears.
// Budget is small since UIHostingController fires for every SwiftUI-hosted
// screen in the app, not just the feed - most calls are expected to find no
// qualifying image and that's normal, only worth seeing a handful of times.
static NSInteger BeaDiagHierarchyDumpsRemaining = 3;

void BeaLogViewHierarchy(UIView *view, NSInteger depth) {
	if (depth > 6) return; // SwiftUI-hosted trees can get deep; cap it
	NSMutableString *indent = [NSMutableString string];
	for (NSInteger i = 0; i < depth; i++) [indent appendString:@"  "];
	NSLog(@"[Bea][diag]%@%@ frame=%@ hidden=%d alpha=%.2f isImageView=%d",
		indent, NSStringFromClass([view class]), NSStringFromCGRect(view.frame),
		view.hidden, view.alpha, [view isKindOfClass:[UIImageView class]]);
	for (UIView *subview in view.subviews) {
		BeaLogViewHierarchy(subview, depth + 1);
	}
}

// FeaturePOVPresentation.POVPostHostingCollectionViewCell (an earlier attempt)
// resolved fine but its layoutSubviews never fired - that class turns out to
// belong to BeReal's separate POV video feature, not the main friends feed,
// which has no plain UIKit cell class of its own at all. Hooking Apple's
// public UIHostingController instead - see the interface comment in Tweak.h
// for why this should be far more stable than guessing at BeReal's internal
// class names again.
%hook UIHostingController
%property (nonatomic, strong) BeaButton *downloadButton;
%property (nonatomic, strong) UIView *downloadButtonAnchor;

- (void)viewDidLayoutSubviews {
	%orig;

	UIView *root = [self view];
	if (!root) return;

	// Hosting controllers can get their content replaced/rebuilt (e.g. this
	// one gets reused for a different screen, or the feed page it's hosting
	// changes). If the image view we last anchored to is no longer part of
	// this controller's view, tear down and re-attach against what's showing
	// now.
	if ([self downloadButton] && (![self downloadButtonAnchor] || ![[self downloadButtonAnchor] isDescendantOfView:root])) {
		[[self downloadButton] removeFromSuperview];
		[self setDownloadButton:nil];
		[self setDownloadButtonAnchor:nil];
	}

	if ([self downloadButton]) return;

	// Anchor to the actual largest qualifying photo rather than this
	// controller's own view edges - most UIHostingController instances in the
	// app aren't showing a BeReal photo at all (settings, profile, etc.), and
	// the >=400pt width filter in qualifyingImageViewsInView: is what keeps
	// this scoped to real BeReal photos instead of firing everywhere.
	UIView *anchor = [BeaDownloader qualifyingImageViewsInView:root].firstObject;

	if (!anchor) {
		if (BeaDiagHierarchyDumpsRemaining > 0) {
			BeaDiagHierarchyDumpsRemaining--;
			NSLog(@"[Bea][diag] viewDidLayoutSubviews fired on UIHostingController (rootView=%@, subviews=%lu) but found no qualifying UIImageView. Dumping hierarchy:",
				NSStringFromClass([root class]), (unsigned long)[[root subviews] count]);
			BeaLogViewHierarchy(root, 0);
		}
		return;
	}

	NSLog(@"[Bea][diag] Anchoring download button to %@ frame=%@", NSStringFromClass([anchor class]), NSStringFromCGRect(anchor.frame));

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

%hook UIViewController
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
	// UIHostingController is Apple's own public class (SwiftUI framework), so
	// unlike BeReal's own Swift classes it may or may not be module-qualified
	// for ObjC - try both.
	Class hostingController = objc_getClass("SwiftUI.UIHostingController");
	NSString *resolvedVia = @"qualified name";
	if (!hostingController) {
		hostingController = objc_getClass("UIHostingController");
		resolvedVia = @"bare name";
	}
	// TEMPORARY - see BeaLogViewHierarchy above.
	if (hostingController) {
		NSLog(@"[Bea][diag] UIHostingController resolved via %@: %@", resolvedVia, hostingController);
	} else {
		NSLog(@"[Bea][diag] UIHostingController FAILED to resolve via either name - the download button hook will never install.");
	}

	%init(
	  UIHostingController = hostingController,
      HomeViewController = objc_getClass("BeReal.HomeViewController"),
	  AdvertsDataNativeViewContainer = objc_getClass("AdvertsData.AdvertNativeViewContainer")
	);
}