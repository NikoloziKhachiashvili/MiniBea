#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface BeaDownloader : NSObject
+ (void)downloadImage:(id)sender;
+ (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo;
// Recursively finds BeReal's actual photo image views under root, deduped and
// sorted by displayed area descending (largest/most prominent first). Used
// both to pick which images to save and, by BeaButton's host cell hook, to
// find a stable anchor to position the download button against.
+ (NSArray<UIImageView *> *)qualifyingImageViewsInView:(UIView *)root;
// Walks up from anchor's superview looking for the smallest ancestor (short
// of root) that itself contains a full front+back pair. The feed keeps
// adjacent posts partially on-screen for smooth swiping, so a single post's
// own local container (this) is what qualifyingImageViewsInView: needs to be
// scoped to - anything wider can pick up a neighboring post's photo instead
// of this post's own second (usually much smaller) camera.
+ (UIView *)localContainerForAnchor:(UIView *)anchor upToRoot:(UIView *)root;
// Whether view's frame currently intersects its own window's bounds. Used to
// tell a scrolled-away anchor apart from one that's still genuinely visible -
// isDescendantOfView: alone stays true long after a post has scrolled off
// screen, until BeReal's own view recycling actually tears it down.
+ (BOOL)isViewOnScreen:(UIView *)view;
// SwiftUI-bridged wrapper/layout views commonly ship with interaction
// disabled, only re-enabling it on specific interactive children - a button
// added under such an ancestor never receives touches regardless of its own
// setting, since hit-testing stops descending as soon as it hits a disabled
// ancestor. Forces it back on from view up to and including root.
+ (void)enableUserInteractionFromView:(UIView *)view upToRoot:(UIView *)root;
@end