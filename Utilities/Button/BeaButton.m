#import "BeaButton.h"

@implementation BeaButton
+ (instancetype)downloadButton {
    BeaButton *downloadButton = [BeaButton buttonWithType:UIButtonTypeRoundedRect];
    [downloadButton setTitle:@"" forState:UIControlStateNormal];

	UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:19];
	UIImage *downloadImage = [UIImage systemImageNamed:@"arrow.down.circle.fill" withConfiguration:config];
	downloadImage = [downloadImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];

	downloadButton.layer.shadowColor = [[UIColor blackColor] CGColor];
    downloadButton.layer.shadowOffset = CGSizeMake(0, 0);
    downloadButton.layer.shadowRadius = 3;
    downloadButton.layer.shadowOpacity = 0.5;

    [downloadButton setImage:downloadImage forState:UIControlStateNormal];
    [downloadButton setTintColor:[UIColor whiteColor]];
    [downloadButton sizeToFit];
	downloadButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
    downloadButton.translatesAutoresizingMaskIntoConstraints = NO;
    [downloadButton addTarget:[BeaDownloader class] action:@selector(downloadImage:) forControlEvents:UIControlEventTouchUpInside];
    
    return downloadButton;
}

+ (instancetype)uploadButton {
    BeaButton *uploadButton = [BeaButton buttonWithType:UIButtonTypeRoundedRect];
    [uploadButton setTitle:@"" forState:UIControlStateNormal];

	UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:22];
	UIImage *plusImage = [UIImage systemImageNamed:@"plus.circle.fill" withConfiguration:config];
	plusImage = [plusImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];

	uploadButton.layer.shadowColor = [[UIColor blackColor] CGColor];
    uploadButton.layer.shadowOffset = CGSizeMake(0, 0);
    uploadButton.layer.shadowRadius = 3;
    uploadButton.layer.shadowOpacity = 0.5;

    [uploadButton setImage:plusImage forState:UIControlStateNormal];
    [uploadButton setTintColor:[UIColor whiteColor]];
    [uploadButton sizeToFit];
    uploadButton.translatesAutoresizingMaskIntoConstraints = NO;

    return uploadButton;
}

- (void)toggleVisibilityWithGestureRecognizer:(UIGestureRecognizer *)gestureRecognizer {
    if ((gestureRecognizer.numberOfTouches < 2 && [gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]]) || gestureRecognizer.state == 3) {
        if (gestureRecognizer.state == 2) return;
        [UIView animateWithDuration:0.2 animations:^{
            self.alpha = 1;
        }];
    } else if ((gestureRecognizer.state == 1 || gestureRecognizer.state == 2)) {
        [UIView animateWithDuration:0.2 animations:^{
            self.alpha = 0;
        }];
    }
}
@end