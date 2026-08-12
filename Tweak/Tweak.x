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
	NSLog(@"[Bea][diag]%{public}@%{public}@ frame=%{public}@ hidden=%d alpha=%.2f isImageView=%d",
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
// Own named %group since it's %init'd separately (and later) from every
// other hook in this file - see BeaTryHookUIHostingController below. Logos
// only allows the default/"ungrouped" %init to be called once per file.
%group BeaSwiftUIGroup
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
			NSLog(@"[Bea][diag] viewDidLayoutSubviews fired on UIHostingController (rootView=%{public}@, subviews=%lu) but found no qualifying UIImageView. Dumping hierarchy:",
				NSStringFromClass([root class]), (unsigned long)[[root subviews] count]);
			BeaLogViewHierarchy(root, 0);
		}
		return;
	}

	NSLog(@"[Bea][diag] Anchoring download button to %{public}@ frame=%{public}@", NSStringFromClass([anchor class]), NSStringFromCGRect(anchor.frame));

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
%end

// TEMPORARY - the previous attempt (guessing "SwiftUI.UIHostingController"/
// "UIHostingController" and waiting via dyld image callbacks) never resolved
// at all, silently, across an entire test session - no log ever fired,
// meaning it's not just a wrong name, the guess never became true. Rather
// than guess a third name, ask the runtime directly what's actually loaded.
static NSInteger BeaClassScansRemaining = 3;

void BeaLogAllHostingClasses(void) {
	int numClasses = objc_getClassList(NULL, 0);
	if (numClasses <= 0) {
		NSLog(@"[Bea][diag] objc_getClassList reported 0 classes");
		return;
	}

	Class *classes = (Class *)malloc(sizeof(Class) * (unsigned long)numClasses);
	if (!classes) return;
	numClasses = objc_getClassList(classes, numClasses);

	// Last scan showed mostly <private> (iOS's unified logging redacts %s/%@
	// dynamic content by default) - {public} forces our own diagnostic output
	// to actually be visible. Also narrowed from *Hosting* (281 matches, almost
	// all unrelated system-framework internals) to *HostingController*, which
	// still catches UIHostingController and its generic-specialization mangled
	// forms (_TtGC7SwiftUI19UIHostingController<...>) while cutting the noise.
	NSInteger found = 0;
	for (int i = 0; i < numClasses; i++) {
		const char *name = class_getName(classes[i]);
		if (name && strstr(name, "HostingController")) {
			NSLog(@"[Bea][diag] Loaded class matching *HostingController*: %{public}s (superclass: %{public}@)",
				name, NSStringFromClass(class_getSuperclass(classes[i])));
			found++;
		}
	}
	NSLog(@"[Bea][diag] Scanned %d loaded classes, %ld matched *HostingController*", numClasses, (long)found);
	free(classes);
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

// TEMPORARY - see BeaLogAllHostingClasses above. viewDidAppear: fires on
// every screen transition, so by the third one plenty of the app (including
// whatever the feed uses) should be loaded.
- (void)viewDidAppear:(BOOL)animated {
	%orig;
	if (BeaClassScansRemaining > 0) {
		BeaClassScansRemaining--;
		NSLog(@"[Bea][diag] viewDidAppear on %{public}@ - scanning loaded classes", NSStringFromClass([self class]));
		BeaLogAllHostingClasses();
	}
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

// UIHostingController lives in SwiftUI.framework, which - unlike BeReal's own
// classes, always present in the main executable - may be lazily loaded and
// not yet mapped into the process when %ctor runs (dylibs load very early,
// typically before main()). objc_getClass returning Nil for it at ctor time
// doesn't mean the class doesn't exist, just that it isn't registered *yet*.
// _dyld_register_func_for_add_image's callback fires once for every image
// already loaded at registration time, then again for every future image
// load, so this catches SwiftUI whether it's loaded before or after us.
static BOOL BeaHostingControllerHooked = NO;
static NSInteger BeaImageCallbackCount = 0;

void BeaTryHookUIHostingController(const struct mach_header *mh, intptr_t vmaddr_slide) {
	// TEMPORARY - confirms the callback is actually firing at all, since last
	// time neither the success nor a (missing) failure log ever appeared.
	BeaImageCallbackCount++;
	if (BeaImageCallbackCount == 1 || BeaImageCallbackCount % 50 == 0) {
		NSLog(@"[Bea][diag] dyld add-image callback invocation #%ld", (long)BeaImageCallbackCount);
	}

	if (BeaHostingControllerHooked) return;

	Class hostingController = objc_getClass("SwiftUI.UIHostingController");
	NSString *resolvedVia = @"qualified name";
	if (!hostingController) {
		hostingController = objc_getClass("UIHostingController");
		resolvedVia = @"bare name";
	}
	if (!hostingController) return;

	BeaHostingControllerHooked = YES;
	// TEMPORARY - see BeaLogViewHierarchy above.
	NSLog(@"[Bea][diag] UIHostingController resolved via %{public}@ (image load callback #%ld): %{public}@", resolvedVia, (long)BeaImageCallbackCount, hostingController);

	%init(BeaSwiftUIGroup, UIHostingController = hostingController);
}

%ctor {
	%init(
      HomeViewController = objc_getClass("BeReal.HomeViewController"),
	  AdvertsDataNativeViewContainer = objc_getClass("AdvertsData.AdvertNativeViewContainer")
	);

	_dyld_register_func_for_add_image(BeaTryHookUIHostingController);
}