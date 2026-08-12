#import "BeaDownloader.h"
#import <objc/runtime.h>

static const void *BeaSearchRootKey = &BeaSearchRootKey;

// Tracks an in-flight save of one BeReal's images (front + back) so the
// checkmark/re-enable only fires once, after every image has finished saving.
@interface BeaDownloadContext : NSObject
@property (nonatomic, weak) UIButton *button;
@property (nonatomic, assign) NSInteger remaining;
@property (nonatomic, assign) BOOL failed;
@end

@implementation BeaDownloadContext
@end

@implementation BeaDownloader
+ (void)downloadImage:(id)sender {
	UIButton *button = (UIButton *)sender;
	// The button lives on the window now (see setSearchRoot:forButton: and
	// Tweak.x), so button.superview is the window, not the post - the real
	// search scope was recorded separately at creation time.
	UIView *root = objc_getAssociatedObject(button, BeaSearchRootKey) ?: button.superview;
	if (!root) return;

	NSArray<UIImageView *> *sorted = [self qualifyingImageViewsInView:root];

	// Largest displayed frame first (back camera in the normal, un-swapped
	// state), capped at 2 since a BeReal is exactly two photos.
	NSUInteger saveCount = MIN(sorted.count, (NSUInteger)2);
	if (saveCount == 0) return;

	NSArray<UIImageView *> *toSave = [sorted subarrayWithRange:NSMakeRange(0, saveCount)];

	button.enabled = NO;

	BeaDownloadContext *context = [BeaDownloadContext new];
	context.button = button;
	context.remaining = toSave.count;
	context.failed = NO;

	for (UIImageView *imageView in toSave) {
		void *contextInfo = (void *)CFBridgingRetain(context);
		UIImageWriteToSavedPhotosAlbum(imageView.image, self, @selector(image:didFinishSavingWithError:contextInfo:), contextInfo);
	}
}

+ (BOOL)isViewOnScreen:(UIView *)view {
	UIWindow *window = view.window;
	if (!window) return NO;
	CGRect frameInWindow = [view convertRect:view.bounds toView:nil];
	return CGRectIntersectsRect(frameInWindow, window.bounds);
}

+ (BOOL)isAnchorDisplayedProminently:(UIView *)anchor {
	UIWindow *window = anchor.window;
	if (!window) return NO;
	CGRect frameInWindow = [anchor convertRect:anchor.bounds toView:nil];
	if (!CGRectIntersectsRect(frameInWindow, window.bounds)) return NO;

	// Only used to decide whether to create/keep the download button - never
	// to filter which images actually get searched/downloaded, since the
	// front camera's PiP is legitimately much narrower than the back camera
	// and must still count as a qualifying image there. The "swipe down for
	// a grid of everyone's BeReals" view reuses the same kind of
	// full-resolution image views the single-post feed does, just displayed
	// as small thumbnails, and small always-present chrome elsewhere (nav
	// icons, etc.) can otherwise also intersect the window trivially.
	// Requiring near-full post width rules both out as button anchors.
	CGRect intersection = CGRectIntersection(frameInWindow, window.bounds);
	return intersection.size.width >= window.bounds.size.width * 0.6;
}

+ (NSArray<UIImageView *> *)qualifyingImageViewsInView:(UIView *)root {
	NSMutableArray<UIImageView *> *candidates = [NSMutableArray array];
	[self collectImageViewsInView:root result:candidates];

	if (candidates.count == 0) return @[];

	// BeReal's feed is a pager that keeps the next post's content mounted
	// off-screen for smooth swiping, so `root` (a shared container VC's view)
	// can contain more than one post's images at once. Restrict to images
	// whose frame actually falls within the screen so we don't pick up a
	// neighboring, not-yet-visible post's photo instead of (or alongside) the
	// one actually being viewed - this is what caused the button to anchor to
	// every other post, and downloads to grab an extra photo from the post
	// next to the one tapped.
	NSMutableArray<UIImageView *> *onScreen = [NSMutableArray array];
	for (UIImageView *imageView in candidates) {
		if ([self isViewOnScreen:imageView]) {
			[onScreen addObject:imageView];
		}
	}

	if (onScreen.count == 0) return @[];

	// Process visible views before hidden ones so dedupe keeps the copy with
	// meaningful on-screen geometry (BeReal keeps a hidden copy of whichever
	// image isn't currently the large frame).
	NSMutableArray<UIImageView *> *visible = [NSMutableArray array];
	NSMutableArray<UIImageView *> *hidden = [NSMutableArray array];
	for (UIImageView *imageView in onScreen) {
		if ([self isView:imageView visibleWithinRoot:root]) {
			[visible addObject:imageView];
		} else {
			[hidden addObject:imageView];
		}
	}

	NSMutableArray<UIImageView *> *ordered = [NSMutableArray arrayWithArray:visible];
	[ordered addObjectsFromArray:hidden];

	NSMutableSet *seenKeys = [NSMutableSet set];
	NSMutableArray<UIImageView *> *uniqueImageViews = [NSMutableArray array];
	for (UIImageView *imageView in ordered) {
		id key = [self dedupeKeyForImageView:imageView];
		if ([seenKeys containsObject:key]) continue;
		[seenKeys addObject:key];
		[uniqueImageViews addObject:imageView];
	}

	return [uniqueImageViews sortedArrayUsingComparator:^NSComparisonResult(UIImageView *a, UIImageView *b) {
		CGRect frameA = [a convertRect:a.bounds toView:nil];
		CGRect frameB = [b convertRect:b.bounds toView:nil];
		CGFloat areaA = frameA.size.width * frameA.size.height;
		CGFloat areaB = frameB.size.width * frameB.size.height;
		if (areaA > areaB) return NSOrderedAscending;
		if (areaA < areaB) return NSOrderedDescending;
		return NSOrderedSame;
	}];
}

+ (UIView *)localContainerForAnchor:(UIView *)anchor upToRoot:(UIView *)root {
	// Adjacent posts are always at least partially on-screen (the feed peeks
	// the next/previous post at the top/bottom edge for swipe affordance), so
	// the on-screen check in qualifyingImageViewsInView: alone can't tell a
	// peeking neighbor's photo apart from this post's own second (usually much
	// smaller) camera. View-tree proximity can: front and back camera image
	// views of the same post are near each other in the hierarchy, while a
	// different post's images live under a completely different branch.
	// Walk up from the anchor looking for the smallest ancestor that already
	// contains a full pair on its own - that's the post's own local container.
	UIView *candidate = anchor.superview;
	UIView *fallback = candidate ?: anchor;
	NSInteger levelsWalked = 0;
	while (candidate && candidate != root && levelsWalked < 12) {
		if ([self qualifyingImageViewsInView:candidate].count >= 2) {
			return candidate;
		}
		fallback = candidate;
		candidate = candidate.superview;
		levelsWalked++;
	}
	return fallback;
}

+ (void)enableUserInteractionFromView:(UIView *)view upToRoot:(UIView *)root {
	UIView *current = view;
	while (current) {
		current.userInteractionEnabled = YES;
		if (current == root) break;
		current = current.superview;
	}
}

+ (void)setSearchRoot:(UIView *)root forButton:(UIButton *)button {
	objc_setAssociatedObject(button, BeaSearchRootKey, root, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (void)enableUserInteractionRecursivelyInView:(UIView *)view {
	view.userInteractionEnabled = YES;
	for (UIView *subview in view.subviews) {
		[self enableUserInteractionRecursivelyInView:subview];
	}
}

+ (BOOL)view:(UIView *)view containsDescendantOfClass:(Class)klass {
	if ([view isKindOfClass:klass]) return YES;
	for (UIView *subview in view.subviews) {
		if ([self view:subview containsDescendantOfClass:klass]) return YES;
	}
	return NO;
}

+ (void)collectGatingLabelsInView:(UIView *)view result:(NSMutableArray<UILabel *> *)result {
	if ([view isKindOfClass:[UILabel class]]) {
		UILabel *label = (UILabel *)view;
		if ([label.text.lowercaseString containsString:@"to view"]) {
			[result addObject:label];
		}
	}
	for (UIView *subview in view.subviews) {
		[self collectGatingLabelsInView:subview result:result];
	}
}

+ (void)hideGatingOverlaysInView:(UIView *)root excludingImages:(NSArray<UIImageView *> *)images {
	NSMutableArray<UILabel *> *labels = [NSMutableArray array];
	[self collectGatingLabelsInView:root result:labels];
	if (labels.count == 0) return;

	for (UILabel *label in labels) {
		UIView *candidate = label.superview;
		UIView *overlay = nil;
		NSInteger levelsWalked = 0;

		while (candidate && candidate != root && levelsWalked < 10) {
			BOOL containsPhoto = NO;
			for (UIImageView *imageView in images) {
				if ([imageView isDescendantOfView:candidate]) {
					containsPhoto = YES;
					break;
				}
			}

			if (!containsPhoto && [self view:candidate containsDescendantOfClass:[UIButton class]]) {
				overlay = candidate;
				break;
			}

			// Any wider ancestor will still contain the photo too - there's
			// no scope above this point that has the overlay's controls
			// without the actual post content, so stop widening.
			if (containsPhoto) break;

			candidate = candidate.superview;
			levelsWalked++;
		}

		if (overlay) {
			overlay.hidden = YES;
		} else if (!label.hidden) {
			// No safely-scoped container found - at minimum hide the label
			// itself so its text stops covering the photo.
			label.hidden = YES;
		}
	}
}

+ (void)collectImageViewsInView:(UIView *)view result:(NSMutableArray<UIImageView *> *)result {
	// Deliberately does not prune hidden/zero-alpha subtrees here (unlike the
	// old class-name-based search) - the front camera's image view may live in
	// one of those, and we need it collected so it can be saved too.
	if ([view isKindOfClass:[UIImageView class]]) {
		UIImageView *imageView = (UIImageView *)view;
		// BeReal photos are ~1500x2000; this filters out avatars, reaction
		// thumbnails, and the download button's own SF Symbol image view.
		if (imageView.image && imageView.image.size.width >= 400) {
			[result addObject:imageView];
		}
	}

	for (UIView *subview in view.subviews) {
		[self collectImageViewsInView:subview result:result];
	}
}

+ (BOOL)isView:(UIView *)view visibleWithinRoot:(UIView *)root {
	UIView *current = view;
	while (current) {
		if (current.hidden || current.alpha <= 0.0) {
			return NO;
		}
		if (current == root) break;
		current = current.superview;
	}
	return YES;
}

+ (id)dedupeKeyForImageView:(UIImageView *)imageView {
	// SDWebImage is already linked into the BeReal binary; if this image view
	// is backed by it, its source URL is the most reliable identity to dedupe
	// on (a swapped/hidden copy of the same photo shares the same URL).
	if ([imageView respondsToSelector:@selector(sd_imageURL)]) {
		id url = [imageView valueForKey:@"sd_imageURL"];
		if (url) return url;
	}

	if (imageView.image) {
		return [NSValue valueWithNonretainedObject:imageView.image];
	}

	return [NSValue valueWithNonretainedObject:imageView];
}

+ (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo {
	BeaDownloadContext *context = (BeaDownloadContext *)CFBridgingRelease(contextInfo);

	// UIImageWriteToSavedPhotosAlbum's completion isn't guaranteed to land on
	// the main thread, and with two images in flight it can arrive from two
	// threads at once - serialize the shared counter through the main queue.
	dispatch_async(dispatch_get_main_queue(), ^{
		if (error) {
			NSLog(@"[Bea]Error saving image: %@", error.localizedDescription);
			context.failed = YES;
		}

		context.remaining -= 1;
		if (context.remaining > 0) return;

		if (context.failed) {
			// Leave the button as-is (no checkmark) but re-enable it - it was
			// disabled before the saves started and must not get stuck.
			context.button.enabled = YES;
		} else {
			[self flashCheckmarkOnButton:context.button];
		}
	});
}

+ (void)flashCheckmarkOnButton:(UIButton *)button {
	if (!button) return;

	UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:19];
	UIImage *checkmarkImage = [UIImage systemImageNamed:@"checkmark.circle.fill" withConfiguration:config];
	[UIView transitionWithView:button duration:0.2 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
	[button setImage:checkmarkImage forState:UIControlStateNormal];
	[button setEnabled:NO];
	[button.imageView setTintColor:[UIColor colorWithRed:122.0/255.0 green:255.0/255.0 blue:108.0/255.0 alpha:1.0]];} completion:nil];

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		UIImage *downloadImage = [UIImage systemImageNamed:@"arrow.down.circle.fill" withConfiguration:config];
		[UIView transitionWithView:button duration:0.2 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
			[button setImage:downloadImage forState:UIControlStateNormal];
			[button.imageView setTintColor:[UIColor whiteColor]];
			[button setEnabled:YES];
		} completion:nil];
    });
}
@end
