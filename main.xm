#import <UIKit/UIKit.h>
#include <dlfcn.h>
#import "libobjcipc/objcipc.h"
#import <libactivator/libactivator.h>

#define SuppressPerformSelectorLeakWarning(Stuff) \
		do { \
			_Pragma("clang diagnostic push") \
			_Pragma("clang diagnostic ignored \"-Warc-performSelector-leaks\"") \
			Stuff; \
			_Pragma("clang diagnostic pop") \
		} while (0)

@interface ControlF : NSObject <LAListener>
@end

@interface UIApplication (ControlF)
- (id)_accessibilityFrontMostApplication;
@end

@interface SBApplication : NSObject
- (id)bundleIdentifier;
@end

@interface UIView (ControlF)

- (NSArray*)allSubviews;

@end

@implementation UIView (ControlF)

- (NSArray*)allSubviews
{
	NSMutableArray *arr = [NSMutableArray new];
	[arr addObject:self];
	for(UIView *subview in self.subviews) {
		[arr addObjectsFromArray:(NSArray*)[subview allSubviews]];
	}
	return arr;
}

@end

static NSMutableArray *registeredApps = [NSMutableArray array];
static NSArray *blacklist = @[@"com.apple.sharingd", @"com.apple.itunesstored", @"com.apple.assistivetouchd"];

static NSString *centreTitle(NSString *bundleID)
{
	NSArray *strings = [bundleID componentsSeparatedByString:@"."];
	return [NSString stringWithFormat:@"com.mootjeuh.MessagingCentre.%@", [strings lastObject]];
}

static NSString *IPFunction(NSString *bundleID, NSString *function)
{
	return [NSString stringWithFormat:@"%@-%@", centreTitle(bundleID), function];
}

static void searchForSelector(id view, SEL action, SEL submethod, NSMutableArray *subviews, NSString *predicate)
{
	if([view respondsToSelector:action]) {
		id result;
		
		SuppressPerformSelectorLeakWarning(
			result = [view performSelector:action];
		);
		
		if(submethod) {
			if([result respondsToSelector:submethod]) {
				SuppressPerformSelectorLeakWarning(
					result = [result performSelector:submethod];
				);
			}
		}
		
		if(result && ![result isEqualToString:@""]) {
			if([[result lowercaseString] containsString:[predicate lowercaseString]]) {
				[subviews addObject:view];
			}
		}
	}
}

static NSArray *search(NSString *keyword)
{
	NSMutableArray *subviews = [NSMutableArray array];
	
	for(id view in [[UIApplication sharedApplication].keyWindow allSubviews]) {
		searchForSelector(view, @selector(text), nil, subviews, keyword);
		searchForSelector(view, @selector(textLabel), @selector(text), subviews, keyword);
		searchForSelector(view, @selector(title), nil, subviews, keyword);
		searchForSelector(view, @selector(titleLabel), @selector(text), subviews, keyword);
		searchForSelector(view, @selector(attributedText), @selector(string), subviews, keyword);
		searchForSelector(view, @selector(label), @selector(text), subviews, keyword);
	}
	
	return subviews;
}

static void presentAlert(UIViewController *viewController)
{
	UIAlertController *alert =	  [UIAlertController
								  alertControllerWithTitle:@"Search"
								  message:@"Type in the text you want to find"
								  preferredStyle:UIAlertControllerStyleAlert];
	
	UIAlertAction *ok = [UIAlertAction actionWithTitle:@"Search" style:UIAlertActionStyleDefault
											   handler:^(UIAlertAction * action) {
												   UITextField *textField = alert.textFields[0];
												   NSArray *results = search(textField.text);
												   if([results count] > 0) {
													   for(int i = [results count]-1; i > -1; i--) {
														   UIView *result = results[i];
														   result.layer.borderColor = [UIColor redColor].CGColor;
														   result.layer.borderWidth = 1.5;
													   }
												   }
											   }];
	UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleDefault
												   handler:^(UIAlertAction * action) {
													   [alert dismissViewControllerAnimated:YES completion:nil];
												   }];
	
	[alert addAction:cancel];
	[alert addAction:ok];
	
	[alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
		textField.placeholder = @"Query";
	}];
	
	[viewController presentViewController:alert animated:YES completion:nil];
}

@implementation ControlF

- (void)activator:(LAActivator*)activator receiveEvent:(LAEvent*)event
{
	SBApplication *currOpen = [[%c(SpringBoard) sharedApplication] _accessibilityFrontMostApplication];
	if(currOpen) {
		dispatch_async(dispatch_get_main_queue(),^{
			[%c(CTRLFIPC) sendMessageToAppWithIdentifier:[currOpen bundleIdentifier] messageName:IPFunction([currOpen bundleIdentifier], @"ControlF") dictionary:nil replyHandler:nil];
		});
	} else {
		presentAlert([UIApplication sharedApplication].keyWindow.rootViewController);
	}
	[event setHandled:YES];
}

- (void)activator:(LAActivator*)activator abortEvent:(LAEvent*)event
{
	NSLog(@"ControlF aborted");
}

- (NSString *)activator:(LAActivator *)activator requiresLocalizedGroupForListenerName:(NSString *)listenerName {
	return @"Tweaks";
}
- (NSString *)activator:(LAActivator *)activator requiresLocalizedTitleForListenerName:(NSString *)listenerName {
	return @"ControlF";
}
- (NSString *)activator:(LAActivator *)activator requiresLocalizedDescriptionForListenerName:(NSString *)listenerName {
	return @"Add CTRL+F functionality to any app";
}
- (NSArray *)activator:(LAActivator *)activator requiresCompatibleEventModesForListenerWithName:(NSString *)listenerName {
	return [NSArray arrayWithObjects:@"springboard", @"lockscreen", @"application", nil];
}

@end

%hook UIApplication

+ (UIApplication*)sharedApplication
{
	NSString *bundleIdentifier = [NSBundle mainBundle].bundleIdentifier;
	if(![bundleIdentifier isEqualToString:@""] && ![blacklist containsObject:bundleIdentifier]) {
		if(![registeredApps containsObject:[NSBundle mainBundle].bundleIdentifier]) {
			[registeredApps addObject:bundleIdentifier];
			dispatch_async(dispatch_get_main_queue(), ^{
				[%c(CTRLFIPC) registerIncomingMessageFromSpringBoardHandlerForMessageName:IPFunction(bundleIdentifier, @"ControlF") handler:^NSDictionary *(NSDictionary *message) {
					presentAlert([UIApplication sharedApplication].keyWindow.rootViewController);
					return nil;
				}];
			});
		}
	}
	return %orig;
}

%end

%ctor {
	if([[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
		NSString *listenerName = @"ControlF";
		dlopen("/usr/lib/libactivator.dylib", RTLD_LAZY);
		static ControlF *listener = [ControlF new];
		id la = [%c(LAActivator) sharedInstance];
		if([la respondsToSelector:@selector(hasSeenListenerWithName:)] && [la respondsToSelector:@selector(assignEvent:toListenerWithName:)]) {
			if(![la hasSeenListenerWithName:listenerName]) {
				[la registerListener:listener forName:@"ControlF"];
			}
		}
		[[%c(LAActivator) sharedInstance] registerListener:listener forName:listenerName];
	}
}