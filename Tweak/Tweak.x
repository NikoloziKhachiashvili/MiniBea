#import "Tweak.h"
#import <os/log.h>

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
//
// %property doesn't work here the way it did for MediaView/UIHostingController
// stubs: those were classes *we* declared via a stub @interface in Tweak.h, so
// Logos's generated accessors matched a real (if fake) interface. UIViewController
// is Apple's own already-fully-declared SDK class, and the compiler rejects
// calling selectors it never declared ("no visible @interface... declares the
// selector"). Associated objects via the plain runtime API sidestep this
// entirely - no property/interface declaration needed at all.
static const void *BeaDownloadButtonKey = &BeaDownloadButtonKey;
static const void *BeaDownloadButtonAnchorKey = &BeaDownloadButtonAnchorKey;

// Temporary: dumps whatever's mounted in the top ~140pt of the screen (nav/
// title chrome), re-logging per controller whenever that content's shape
// actually changes, so the real "+" upload hook can target the actual
// current class/structure of the BeReal wordmark logo instead of guessing at
// a name that changed in the rewrite. Remove once that hook is wired up.
// Filter device logs for "[BeaDiag]".
//
// The first round logged once per controller on its very first layout pass,
// which mostly caught still-loading placeholders (a bare activity spinner, a
// FloatingBarHostingView with zero children yet) - the same async-mounting
// behavior already seen elsewhere in this file for the gating overlay.
// Re-logging on any change in descendant count catches content that mounts
// after that first pass, without spamming on unchanged re-layouts (e.g. from
// scrolling).
static const void *BeaLoggedTopChromeCountKey = &BeaLoggedTopChromeCountKey;

static NSInteger BeaCountTopChrome(UIView *view, NSInteger depth) {
	if (depth > 6) return 0;
	CGRect frameInWindow = [view convertRect:view.bounds toView:nil];
	if (frameInWindow.origin.y > 140) return 0;

	NSInteger count = 1;
	for (UIView *subview in view.subviews) {
		count += BeaCountTopChrome(subview, depth + 1);
	}
	return count;
}

static void BeaLogTopChrome(UIView *view, UIWindow *window, NSInteger depth) {
	if (!window || depth > 6) return;

	CGRect frameInWindow = [view convertRect:view.bounds toView:nil];
	if (frameInWindow.origin.y > 140) return;

	NSString *accessibilityLabel = view.accessibilityLabel ?: @"";
	NSString *extra = @"";
	if ([view isKindOfClass:[UIImageView class]]) {
		UIImage *image = ((UIImageView *)view).image;
		extra = [NSString stringWithFormat:@"image=%.0fx%.0f", image.size.width, image.size.height];
	} else if ([view isKindOfClass:[UILabel class]]) {
		extra = [NSString stringWithFormat:@"text=%@", ((UILabel *)view).text];
	}

	NSString *indent = [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0];
	os_log(OS_LOG_DEFAULT, "[BeaDiag]%{public}@%{public}@ frame=%{public}@ a11y=%{public}@ %{public}@",
		indent, NSStringFromClass([view class]), NSStringFromCGRect(frameInWindow), accessibilityLabel, extra);

	for (UIView *subview in view.subviews) {
		BeaLogTopChrome(subview, window, depth + 1);
	}
}

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

- (void)viewDidLayoutSubviews {
	%orig;

	UIView *root = [self view];
	if (!root) return;

	UIWindow *window = root.window;

	if (window) {
		NSInteger currentTopChromeCount = BeaCountTopChrome(root, 0);
		NSNumber *lastLoggedCount = objc_getAssociatedObject(self, BeaLoggedTopChromeCountKey);
		if (!lastLoggedCount || lastLoggedCount.integerValue != currentTopChromeCount) {
			objc_setAssociatedObject(self, BeaLoggedTopChromeCountKey, @(currentTopChromeCount), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			os_log(OS_LOG_DEFAULT, "[BeaDiag]==== %{public}@ (n=%{public}ld) ====", NSStringFromClass([self class]), (long)currentTopChromeCount);
			BeaLogTopChrome(root, window, 0);
		}
	}

	NSArray<UIImageView *> *qualifyingImages = [BeaDownloader qualifyingImageViewsInView:root];

	// Gated ("Post to view") posts draw a lock overlay - eye-slash icon,
	// title/body text, and a CTA button - above the photo, separate from and
	// unaffected by the CAFilter blur-removal hook below. Runs unconditionally
	// on every layout pass, since BeReal can (re)mount it at any time, same
	// as the button z-order issue this file already works around.
	[BeaDownloader hideGatingOverlaysInView:root excludingImages:qualifyingImages];

	BeaButton *existingButton = objc_getAssociatedObject(self, BeaDownloadButtonKey);
	UIView *existingAnchor = objc_getAssociatedObject(self, BeaDownloadButtonAnchorKey);

	// Content can get replaced/rebuilt under a given controller (e.g. cell/
	// controller reuse, or navigating to different content). isDescendantOfView:
	// alone isn't enough - a scrolled-away post stays in the hierarchy (just
	// off-screen) until BeReal's own view recycling actually tears it down, so
	// the button would otherwise stick to the previous post long after it's
	// scrolled away. Also require the anchor to still be displayed prominently -
	// the "swipe down" grid view can reuse/resize the same anchor view down to
	// thumbnail size without it ever leaving the hierarchy or the screen.
	if (existingButton && (!existingAnchor || ![existingAnchor isDescendantOfView:root] || ![BeaDownloader isAnchorDisplayedProminently:existingAnchor])) {
		[existingButton removeFromSuperview];
		objc_setAssociatedObject(self, BeaDownloadButtonKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		objc_setAssociatedObject(self, BeaDownloadButtonAnchorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		existingButton = nil;
	}

	// Reject grid-view thumbnails and small chrome elements as anchors - the
	// general on-screen filter inside qualifyingImageViewsInView: is
	// deliberately permissive (it has to accept the front camera's narrow
	// PiP too), so this is the one place that requires the anchor to
	// actually be a full-size, single-post photo.
	UIView *anchor = qualifyingImages.firstObject;
	UIView *localContainer = nil;
	if (anchor && [BeaDownloader isAnchorDisplayedProminently:anchor]) {
		// Search scope stays tied to the post's own local container (not
		// `root`, which can be a shared pager view spanning more than one
		// post).
		UIView *candidateContainer = [BeaDownloader localContainerForAnchor:anchor upToRoot:root];

		// localContainerForAnchor: falls back to returning *something* even
		// when it never found a real front+back pair nearby (e.g. a single
		// incidental >=400pt image on an unrelated screen) - only treat it
		// as valid when it actually found a genuine pair.
		if (candidateContainer && [BeaDownloader qualifyingImageViewsInView:candidateContainer].count >= 2) {
			localContainer = candidateContainer;

			// SwiftUI-bridged layout containers commonly ship with
			// interaction disabled, only opting specific children back in -
			// without this, taps aimed at the post's own content (our
			// button, and BeReal's own tap-to-swap-camera gesture) never
			// reach anything. Runs every pass, not just at button-creation
			// time, in case BeReal re-disables it later the same way it can
			// remount the lock overlay above.
			[BeaDownloader enableUserInteractionFromView:localContainer upToRoot:root];
			[BeaDownloader enableUserInteractionRecursivelyInView:localContainer];
		}
	}

	if (existingButton) {
		// A gated ("Post to view") post's lock overlay can mount, or remount,
		// after our button was added, covering it and silently eating its
		// taps - reassert front position on every layout pass rather than
		// trusting it to stick from creation time.
		if (window) [window bringSubviewToFront:existingButton];
		return;
	}

	if (!anchor || !window || !localContainer) return;

	BeaButton *downloadButton = [BeaButton downloadButton];
	downloadButton.layer.zPosition = 99;

	objc_setAssociatedObject(self, BeaDownloadButtonKey, downloadButton, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(self, BeaDownloadButtonAnchorKey, anchor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	[BeaDownloader setSearchRoot:localContainer forButton:downloadButton];

	// Attach to the window, not the post's own container. A gated post's
	// lock overlay is drawn above the post's content, so no z-order trick
	// scoped to the post's own view tree can out-rank it - the window is
	// above everything in this controller by construction, and staying there
	// (reasserted above) survives the overlay mounting at any point later.
	[window addSubview:downloadButton];
	[window bringSubviewToFront:downloadButton];

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

// Static string analysis of the decrypted BeReal binary (no live device
// needed for this part) turned up a real, NSObject-rooted Swift class -
// BeReal.HasPostedUseCaseImpl - wired directly alongside postRepository and
// blurState in the feed's own dependency graph, making it a much stronger
// candidate for the actual root of the "Post to view" gate than continuing
// to fight the rendered UI after the fact. But the class being visible to
// objc_getClass only proves the *class* is NSObject-rooted - it says nothing
// about whether any individual method is @objc-dynamic (and therefore
// hookable via %hook, which works by swizzling objc_msgSend dispatch) versus
// pure Swift vtable dispatch (invisible to this technique entirely). Rather
// than guess a selector name and burn a round finding out it's wrong, dump
// the real method list at launch - this is the same class_copyMethodList
// technique that resolved the UIHostingController question earlier.
static void BeaLogMethodsOfClass(Class klass, const char *label) {
	if (!klass) {
		os_log(OS_LOG_DEFAULT, "[Bea] %{public}s: class not found at ctor time", label);
		return;
	}

	unsigned int instanceCount = 0;
	Method *instanceMethods = class_copyMethodList(klass, &instanceCount);
	os_log(OS_LOG_DEFAULT, "[Bea] %{public}s: %{public}u instance method(s)", label, instanceCount);
	for (unsigned int i = 0; i < instanceCount; i++) {
		os_log(OS_LOG_DEFAULT, "[Bea]   -[%{public}s %{public}s] type=%{public}s",
			label, sel_getName(method_getName(instanceMethods[i])), method_getTypeEncoding(instanceMethods[i]));
	}
	if (instanceMethods) free(instanceMethods);

	unsigned int classCount = 0;
	Method *classMethods = class_copyMethodList(object_getClass(klass), &classCount);
	os_log(OS_LOG_DEFAULT, "[Bea] %{public}s: %{public}u class method(s)", label, classCount);
	for (unsigned int i = 0; i < classCount; i++) {
		os_log(OS_LOG_DEFAULT, "[Bea]   +[%{public}s %{public}s] type=%{public}s",
			label, sel_getName(method_getName(classMethods[i])), method_getTypeEncoding(classMethods[i]));
	}
	if (classMethods) free(classMethods);
}

%ctor {
	%init(
      HomeViewController = objc_getClass("BeReal.HomeViewController"),
	  AdvertsDataNativeViewContainer = objc_getClass("AdvertsData.AdvertNativeViewContainer")
	);

	os_log(OS_LOG_DEFAULT, "[Bea] tweak loaded, dumping candidate gating classes");
	BeaLogMethodsOfClass(objc_getClass("BeReal.HasPostedUseCaseImpl"), "HasPostedUseCaseImpl");
	BeaLogMethodsOfClass(objc_getClass("BeReal.IsPostViewableUseCaseImpl"), "IsPostViewableUseCaseImpl");
}