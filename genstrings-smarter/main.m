//
//  main.m
//  genstrings-smarter
//
//  Created by Kevin Monahan on 6/27/16.
//  Copyright © 2016 Intrepid Pursuits. All rights reserved.
//

#import <Foundation/Foundation.h>
@import GenStringsSmarterFramework;

// Reference for setting up this project initially: https://colemancda.github.io/programming/2015/02/12/embedded-swift-frameworks-osx-command-line-tools/

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSMutableArray *args = [NSMutableArray arrayWithCapacity:argc];
        for (int i = 1; i < argc; i++) {
            NSString *str = [[NSString alloc] initWithCString:argv[i] encoding:NSUTF8StringEncoding];
            [args addObject:str];
        }

        [[[GenStringsSmarter alloc] init] run: args];
    }
    return 0;
}
