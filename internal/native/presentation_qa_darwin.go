//go:build fuwa_parity_qa

package native

/*
#import <Cocoa/Cocoa.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
static char *qa_json(id value) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    return strdup([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
}
// Only metadata for the QA app's own window is returned; no pixels are captured.
static char *qa_presentation(uintptr_t host) {
    NSWindow *w=(__bridge NSWindow *)(void *)host;
    NSInteger index=-1, i=0;
    NSArray *list=CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly,kCGNullWindowID));
    for (NSDictionary *entry in list) {
        if ([entry[(id)kCGWindowNumber] integerValue]==w.windowNumber) { index=i;break; }
        i++;
    }
    return qa_json(@{@"level":@(w.level),@"visible":@(w.visible),@"order":@(index),
        @"parent":@((uintptr_t)(__bridge void *)w.parentWindow)});
}
static void qa_menu(NSMenu *menu, NSMutableArray *titles) {
    for (NSMenuItem *item in menu.itemArray) {
        if (item.title.length) [titles addObject:item.title];
        if (item.submenu) qa_menu(item.submenu,titles);
    }
}
static char *qa_menu_titles(void) {
    NSMutableArray *titles=[NSMutableArray array];qa_menu(NSApp.mainMenu,titles);return qa_json(titles);
}
*/
import "C"

import "encoding/json"

type PresentationSnapshot struct {
	Level   int
	Visible bool
	Order   int
	Parent  uintptr
}

func QAPresentation(host uintptr) PresentationSnapshot {
	var result PresentationSnapshot
	if err := json.Unmarshal([]byte(take(C.qa_presentation(C.uintptr_t(host)))), &result); err != nil {
		panic(err)
	}
	return result
}
func QAMenuTitles() []string {
	var titles []string
	if err := json.Unmarshal([]byte(take(C.qa_menu_titles())), &titles); err != nil {
		panic(err)
	}
	return titles
}
