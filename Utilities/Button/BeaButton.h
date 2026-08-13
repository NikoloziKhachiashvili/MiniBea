#import <UIKit/UIKit.h>
#import "../Downloader/BeaDownloader.h"

@interface BeaButton : UIButton
+ (instancetype)downloadButton;
+ (instancetype)uploadButton;
- (void)toggleVisibilityWithGestureRecognizer:(UIGestureRecognizer *)gestureRecognizer;
@end