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

%hook POVPostHostingCollectionViewCell
%property (nonatomic, strong) BeaButton *downloadButton;
%property (nonatomic, strong) UIView *downloadButtonAnchor;

- (void)layoutSubviews {
	%orig;

	// UICollectionView reuses cells across different posts as the feed
	// scrolls. If the image view we last anchored the button to is no longer
	// part of this cell (its SwiftUI-hosted content got swapped out), tear
	// down the stale button/constraints and re-attach below against whatever
	// is showing now.
	if ([self downloadButton] && (![self downloadButtonAnchor] || ![[self downloadButtonAnchor] isDescendantOfView:self])) {
		[[self downloadButton] removeFromSuperview];
		[self setDownloadButton:nil];
		[self setDownloadButtonAnchor:nil];
	}

	if ([self downloadButton]) return;

	// Anchor to the actual largest photo in this cell rather than the cell's
	// own edges - we don't know what else (captions, header, buttons) BeReal
	// lays out around it, but we do know where the photo itself ends up.
	UIView *anchor = [BeaDownloader qualifyingImageViewsInView:self].firstObject;
	if (!anchor) return;

	BeaButton *downloadButton = [BeaButton downloadButton];
	downloadButton.layer.zPosition = 99;

	[self setDownloadButton:downloadButton];
	[self setDownloadButtonAnchor:anchor];
	[self addSubview:downloadButton];

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
	// Swift classes are normally exposed to the ObjC runtime as
	// "Module.ClassName", but fall back to the bare name in case this
	// particular class wasn't qualified - cheap, and %init just no-ops a
	// hook group whose class resolves to Nil rather than crashing.
	Class povPostCell = objc_getClass("FeaturePOVPresentation.POVPostHostingCollectionViewCell");
	if (!povPostCell) povPostCell = objc_getClass("POVPostHostingCollectionViewCell");

	%init(
	  POVPostHostingCollectionViewCell = povPostCell,
      HomeViewController = objc_getClass("BeReal.HomeViewController"),
	  AdvertsDataNativeViewContainer = objc_getClass("AdvertsData.AdvertNativeViewContainer")
	);
}