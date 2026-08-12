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
@end