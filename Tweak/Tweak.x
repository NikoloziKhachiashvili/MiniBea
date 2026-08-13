#import "Tweak.h"
#import <os/log.h>
#import <QuartzCore/QuartzCore.h>

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
//
// Tracked per-controller (not globally by anchor object identity - that was
// tried and reverted). BeReal recycles its UIImageView instances as the feed
// scrolls, reusing the same object for a new post rather than creating a
// fresh one - a global map keyed by anchor identity treated a recycled view
// as "already has a button" and never refreshed which post's photos that
// button actually searches, only what it was created with. That caused
// exactly what it was meant to prevent: wrong photos downloaded (stale
// search scope surviving a recycle), missing buttons (a new post silently
// reusing a tracked object instead of being evaluated fresh), and duplicates
// (a genuinely new object existing alongside a stale tracked one) - all
// worse than the single bug it fixed. That original bug - MainTabBarController
// independently rediscovering the same anchor HomeViewHostingController
// already has a button for, and creating its own duplicate, since both
// controllers get their own independent viewDidLayoutSubviews call and
// MainTabBarController's view contains the same post content as a descendant
// (confirmed via the [BeaDiag] logging below) - is instead fixed by scoping
// this whole block to only run on HomeViewHostingController's own pass, so
// no other controller's pass ever reaches this code at all.
static const void *BeaDownloadButtonKey = &BeaDownloadButtonKey;
static const void *BeaDownloadButtonAnchorKey = &BeaDownloadButtonAnchorKey;

// Temporary: dumps whatever's mounted in the top of the screen (nav/title
// chrome), re-logging per controller whenever that content's shape actually
// changes, so the real "+" upload hook can target the actual current
// class/structure of the BeReal wordmark logo instead of guessing at a name
// that changed in the rewrite. Remove once that hook is wired up. Filter
// device logs for "[BeaDiag]".
//
// Round 1 logged once per controller on its very first layout pass, which
// mostly caught still-loading placeholders (a bare activity spinner, a
// FloatingBarHostingView with zero children yet) - the same async-mounting
// behavior already seen elsewhere in this file for the gating overlay.
// Round 2 re-logged on any change in descendant count to catch content that
// mounts later, but kept the same <140pt cutoff - real device data showed
// the scroll-edge blur effect behind the nav area alone runs up to 210pt
// tall in this redesigned "Liquid Glass" chrome, so 140 was too shallow and
// nothing resembling a logo ever showed up under FriendsFeedOverview even
// once fully loaded. Raised the cutoff to comfortably clear that, and added
// accessibilityIdentifier alongside accessibilityLabel - SwiftUI content
// frequently renders without materializing a matching UIImageView/UILabel at
// all (mirrors the gating-overlay Text not bridging to UILabel elsewhere in
// this file), so a UI test identifier may be the only signal a plain
// class/text scan can find.
static const void *BeaLoggedTopChromeCountKey = &BeaLoggedTopChromeCountKey;

static NSInteger BeaCountTopChrome(UIView *view, NSInteger depth) {
	if (depth > 8) return 0;
	CGRect frameInWindow = [view convertRect:view.bounds toView:nil];
	if (frameInWindow.origin.y > 260) return 0;

	NSInteger count = 1;
	for (UIView *subview in view.subviews) {
		count += BeaCountTopChrome(subview, depth + 1);
	}
	return count;
}

static void BeaLogTopChrome(UIView *view, UIWindow *window, NSInteger depth) {
	if (!window || depth > 8) return;

	CGRect frameInWindow = [view convertRect:view.bounds toView:nil];
	if (frameInWindow.origin.y > 260) return;

	NSString *accessibilityLabel = view.accessibilityLabel ?: @"";
	NSString *accessibilityIdentifier = view.accessibilityIdentifier ?: @"";
	NSString *extra = @"";
	if ([view isKindOfClass:[UIImageView class]]) {
		UIImage *image = ((UIImageView *)view).image;
		extra = [NSString stringWithFormat:@"image=%.0fx%.0f", image.size.width, image.size.height];
	} else if ([view isKindOfClass:[UILabel class]]) {
		extra = [NSString stringWithFormat:@"text=%@", ((UILabel *)view).text];
	}

	NSString *indent = [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0];
	os_log(OS_LOG_DEFAULT, "[BeaDiag]%{public}@%{public}@ frame=%{public}@ a11y=%{public}@ id=%{public}@ %{public}@",
		indent, NSStringFromClass([view class]), NSStringFromCGRect(frameInWindow), accessibilityLabel, accessibilityIdentifier, extra);

	for (UIView *subview in view.subviews) {
		BeaLogTopChrome(subview, window, depth + 1);
	}
}

// The BeReal wordmark/logo itself couldn't be found anywhere in the view
// hierarchy across three rounds of diagnostic logging on the home feed - just
// a translucent scroll-edge blur where it visually sits, meaning it's most
// likely drawn directly by SwiftUI's own renderer with no backing UIView at
// all (the same reason the gating overlay's text needed accessibilityLabel
// instead of UILabel.text). Rather than continue chasing an invisible view,
// the "+" button is added independently to the one real, stable, resolvable
// class name found for the home feed screen itself.
static NSString *const BeaHomeViewHostingControllerClassName = @"_TtGC6BeReal25HomeViewHostingControllerVS_8HomeView_";
static const void *BeaUploadButtonKey = &BeaUploadButtonKey;

// Weak so a Home controller BeReal discards gets freed normally - this is
// only ever consulted, never what keeps it alive. Refreshed on every layout
// pass of the Home controller itself, but read from *any* controller's pass
// (see below) since switching away from Home fires the newly-active
// controller's own hook, not Home's - that's the only way to react to
// navigation the button isn't itself present for.
static __weak UIViewController *BeaActiveHomeController = nil;

// Not useful for positioning (its bounding box is the full screen width, see
// the comment on BeaHomeViewHostingControllerClassName above) but still
// useful for visibility: this row hides itself (transform/alpha, not removal)
// when the feed auto-hides its nav chrome on scroll, and mirroring that state
// (via BeaVisibilitySyncTarget below) is the only way the upload button
// doesn't end up floating disconnected from the row it's meant to sit next to.
static UIView *BeaFindViewByClassName(UIView *view, NSString *className, NSInteger depth) {
	if (!view || depth > 20) return nil;
	if ([NSStringFromClass([view class]) isEqualToString:className]) return view;
	for (UIView *subview in view.subviews) {
		UIView *found = BeaFindViewByClassName(subview, className, depth + 1);
		if (found) return found;
	}
	return nil;
}

// Both floating buttons live directly on the window (needed to out-rank the
// gating overlay's own z-order), which means neither respects normal view-
// controller presentation z-ordering on its own. Without this check, a
// controller whose layout pass fires again mid-presentation-transition
// (plausible, and observed) can re-assert a tracked button back on top of a
// freshly-presented modal - e.g. tapping "+" and getting the previous post's
// download button back on top of the upload screen, only clearing once back
// on the feed and scrolled to a new post.
static BOOL BeaHasPresentedModal(UIWindow *window) {
	return window.rootViewController.presentedViewController != nil;
}

// viewDidLayoutSubviews only fires when layout is actually invalidated - the
// feed's own nav row hides itself on scroll via a transform/alpha change,
// not a frame change, so that hook never re-fires for it and polling there
// (the previous approach) missed every scroll-hide entirely. Reading the
// platter's own presentation layer every frame instead reflects whatever's
// actually rendered on screen right now, regardless of which private iOS 26
// "Liquid Glass" mechanism drives the hide animation underneath it.
//
// A CALayer's opacity does not compound into its descendants' own opacity
// property values - it only affects how they're composited visually. If the
// fade is actually applied to an ancestor of the platter (e.g. the nav bar
// or its background) rather than the platter itself, reading the platter's
// own presentationLayer.opacity directly would misreport 1.0 the entire
// time. Walking every ancestor up to the window and multiplying their live
// opacities together mirrors how the fade actually composites on screen,
// regardless of which specific view in the chain it's applied to.
static CGFloat BeaEffectiveOpacity(UIView *view, UIWindow *window) {
	CGFloat opacity = 1.0;
	UIView *current = view;
	while (current && current != window) {
		if (current.isHidden) return 0.0;
		CALayer *presentation = current.layer.presentationLayer ?: current.layer;
		opacity *= presentation.opacity;
		if (opacity <= 0.01) return 0.0;
		current = current.superview;
	}
	return opacity;
}

@interface BeaVisibilitySyncTarget : NSObject
@end

@implementation BeaVisibilitySyncTarget
- (void)bea_tick:(CADisplayLink *)link {
	if (!BeaActiveHomeController) return;
	BeaButton *uploadButton = objc_getAssociatedObject(BeaActiveHomeController, BeaUploadButtonKey);
	if (!uploadButton) return;

	UIView *root = BeaActiveHomeController.view;
	UIWindow *window = root.window;
	BOOL homeOnScreen = window != nil && [BeaDownloader isViewOnScreen:root] && !BeaHasPresentedModal(window);
	if (!homeOnScreen) {
		uploadButton.hidden = YES;
		return;
	}

	UIView *platter = BeaFindViewByClassName(window, @"UIKit.NavigationBarPlatterContainer_v2", 0);
	if (!platter) {
		uploadButton.hidden = YES;
		return;
	}

	CALayer *presentation = platter.layer.presentationLayer ?: platter.layer;
	CGRect frameInWindow = [presentation convertRect:presentation.bounds toLayer:window.layer];
	BOOL onScreen = CGRectIntersectsRect(frameInWindow, window.bounds);
	CGFloat effectiveOpacity = BeaEffectiveOpacity(platter, window);
	uploadButton.hidden = !(onScreen && effectiveOpacity > 0.05);
	uploadButton.alpha = effectiveOpacity;
}
@end

static CADisplayLink *BeaVisibilityDisplayLink;
static BeaVisibilitySyncTarget *BeaVisibilitySyncTargetInstance;

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

	BOOL isHomeController = [NSStringFromClass([self class]) isEqualToString:BeaHomeViewHostingControllerClassName];

	if (isHomeController) {
		BeaActiveHomeController = self;

		if (window && !objc_getAssociatedObject(self, BeaUploadButtonKey)) {
			// A device screenshot showed the actual layout: a circular add-friend
			// icon on the leading edge, the (unreachable, SwiftUI-only) "BeReal."
			// wordmark centered, and the notification bell on the trailing edge,
			// all in one row just below the safe area. UIKit.NavigationBarPlatterContainer_v2
			// (tried previously) turned out to be a full-screen-width invisible
			// wrapper around that whole row, not a small pill around the bell -
			// anchoring to its leading edge was really anchoring to the screen's
			// own edge, which is why the button ended up off-screen. There's a
			// visible gap between the add-friend icon and the wordmark; these
			// fixed offsets land the button there, clear of both.
			BeaButton *uploadButton = [BeaButton uploadButton];
			[uploadButton addTarget:self action:@selector(bea_uploadButtonTapped) forControlEvents:UIControlEventTouchUpInside];
			objc_setAssociatedObject(self, BeaUploadButtonKey, uploadButton, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			[window addSubview:uploadButton];

			[NSLayoutConstraint activateConstraints:@[
				[uploadButton.leadingAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.leadingAnchor constant:64],
				[uploadButton.topAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.topAnchor constant:8]
			]];
		}
	}

	// Upload button visibility (Home-active, nav row auto-hide) is handled
	// continuously by BeaVisibilityDisplayLink instead of here - see its
	// comment for why a layout-pass hook can't observe a transform/alpha-only
	// hide animation.

	NSArray<UIImageView *> *qualifyingImages = [BeaDownloader qualifyingImageViewsInView:root];

	// Gated ("Post to view") posts draw a lock overlay - eye-slash icon,
	// title/body text, and a CTA button - above the photo, separate from and
	// unaffected by the CAFilter blur-removal hook below. Runs unconditionally
	// on every layout pass, since BeReal can (re)mount it at any time, same
	// as the button z-order issue this file already works around.
	[BeaDownloader hideGatingOverlaysInView:root excludingImages:qualifyingImages];

	// The download button search/creation only ever needs to run for the
	// actual home feed controller - see the comment on BeaDownloadButtonKey
	// above for why letting every controller (including ancestors like
	// MainTabBarController that contain the same content as a descendant)
	// run this independently caused duplicate/incorrect buttons.
	if (!isHomeController) return;

	BeaButton *existingButton = objc_getAssociatedObject(self, BeaDownloadButtonKey);
	UIView *existingAnchor = objc_getAssociatedObject(self, BeaDownloadButtonAnchorKey);

	// See BeaHasPresentedModal above - the button lives on the window, so it
	// doesn't respect normal presentation z-ordering on its own and needs to
	// be explicitly hidden while anything (e.g. the upload screen) is
	// presented, rather than only reacting to its own anchor's state.
	if (window && BeaHasPresentedModal(window)) {
		existingButton.hidden = YES;
		return;
	}
	if (existingButton) existingButton.hidden = NO;

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
		// Refresh which post's photos this button actually searches on every
		// pass, even when just reusing it rather than recreating it - BeReal
		// can recycle the same anchor UIImageView instance for a completely
		// different post as the feed scrolls, and this is what keeps the
		// button's search scope in sync with whatever it's currently sitting
		// on instead of silently going stale and downloading whatever post
		// it was originally created for.
		if (localContainer) [BeaDownloader setSearchRoot:localContainer forButton:existingButton];

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

%new
- (void)bea_uploadButtonTapped {
	if (![[BeaTokenManager sharedInstance] BRAccessToken]) return;

	BeaUploadViewController *uploadViewController = [[BeaUploadViewController alloc] init];
	uploadViewController.modalPresentationStyle = UIModalPresentationFullScreen;
	[self presentViewController:uploadViewController animated:YES completion:nil];
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
      AdvertsDataNativeViewContainer = objc_getClass("AdvertsData.AdvertNativeViewContainer")
	);

	BeaVisibilitySyncTargetInstance = [BeaVisibilitySyncTarget new];
	BeaVisibilityDisplayLink = [CADisplayLink displayLinkWithTarget:BeaVisibilitySyncTargetInstance selector:@selector(bea_tick:)];
	// NSRunLoopCommonModes, not just the default mode - a display link added
	// only to the default mode pauses for the entire duration of an active
	// scroll drag (UIScrollView tracking runs the loop in its own tracking
	// mode), which is exactly when this needs to keep firing.
	[BeaVisibilityDisplayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

	os_log(OS_LOG_DEFAULT, "[Bea] tweak loaded, dumping candidate gating classes");
	BeaLogMethodsOfClass(objc_getClass("BeReal.HasPostedUseCaseImpl"), "HasPostedUseCaseImpl");
	BeaLogMethodsOfClass(objc_getClass("BeReal.IsPostViewableUseCaseImpl"), "IsPostViewableUseCaseImpl");
}