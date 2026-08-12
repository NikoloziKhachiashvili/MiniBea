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
@end