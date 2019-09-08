//
//  UIFastProgressBar.m
//  BarMagnet
//
//  Created by Charlotte Tortorella on 27/01/2014.
//  Copyright (c) 2014 Charlotte Tortorella. All rights reserved.
//

#import "UIFastProgressBar.h"

@implementation UIFastProgressBar

- (id)init {
    if (self = [super init]) {
        [self awakeFromNib];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)awakeFromNib {
    [super awakeFromNib];
    self.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.layer.cornerRadius = self.frame.size.height / 2.0;
    self.layer.masksToBounds = YES;
    self.progressTintColor = [UIColor blueColor];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(setNeedsDisplay) name:UIDeviceOrientationDidChangeNotification object:nil];
}

- (void)drawRect:(CGRect)rect {
    CGRect progress = self.frame;
    progress.origin.x = progress.origin.y = 0;
    progress.size.width *= self.progress;
    [self.progressTintColor setFill];
    [[UIBezierPath bezierPathWithRoundedRect:progress cornerRadius:progress.size.height / 2.0] fill];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = self.frame.size.height / 2.0;
}

- (void)setProgress:(double)progress {
    _progress = progress;
    [self setNeedsDisplay];
}

@end
