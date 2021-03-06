/*******************************************************************************
 * Copyright 2012 Jeremy Raymond
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *******************************************************************************/

#import "NPMRenderer.h"
#import "NPMData.h"
#import "NPMNotificationQueue.h"
#import "NPMLog.h"

// Sundown
#import "markdown.h"
#import "html.h"
#import "buffer.h"

@implementation NPMRenderer {
    NSString *_html;
    BOOL _renderNeeded;
    BOOL _renderInProgress;
}

#pragma mark Init

- (id)init
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:@"-init is not a valid initializer for the class NPMRenderer"
                                 userInfo:nil];
    return nil;
}

- (id)initWithData:(NPMData *)data
{
    self = [super init];
    if (self) {
        self.data = data;
        [NPMNotificationQueue addObserver:self selector:@selector(dataChanged:) name:NPMNotificationDataChanged
                                   object:self.data];
        [self render];
    }
    return self;
}

#pragma mark Properties

- (NSString *)html
{
    @synchronized(self) {
        return _html;
    }
}

#pragma mark Internal

- (void)dataChanged:(NSNotification *)notification
{
    [self render];
}

- (void)render
{
    @synchronized(self) {
        if (_renderNeeded) {
            DDLogInfo(@"Render already queued, request ignored");
            return;
        } else if (_renderInProgress) {
            DDLogInfo(@"Render in progress, queued render request");
            _renderNeeded = YES;
            return;
        } else {
            _renderInProgress = YES;
        }
    }
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

    dispatch_async(queue, ^{
        DDLogInfo(@"Rendering");
        NSString *markdown = self.data.text;

        // Render markdown into html with Sundown library
        if (markdown && [markdown length] > 0) {
            const char *cString;
            struct buf *inputBuffer;

            // Copy markdown info input buffer
            cString = [markdown UTF8String];
            inputBuffer = bufnew(strlen(cString));
            bufputs(inputBuffer, cString);

            // Render
            struct sd_callbacks callbacks;
            struct html_renderopt options;
            struct sd_markdown *sdMarkdown;
            struct buf *outputBuffer;
            int extensions = 0;

            extensions |= MKDEXT_TABLES | MKDEXT_FENCED_CODE | MKDEXT_AUTOLINK | MKDEXT_STRIKETHROUGH
                | MKDEXT_SPACE_HEADERS | MKDEXT_SUPERSCRIPT;
            outputBuffer = bufnew(64);
            sdhtml_renderer(&callbacks, &options, 0);
            sdMarkdown = sd_markdown_new(extensions, 16, &callbacks, &options);
            sd_markdown_render(outputBuffer, inputBuffer->data, inputBuffer->size, sdMarkdown);
            sd_markdown_free(sdMarkdown);

            // Save rendered markdown
            char *rendered;

            rendered = malloc((sizeof *rendered) * (outputBuffer->size + 1));
            memcpy(rendered, outputBuffer->data, outputBuffer->size);
            *(rendered + outputBuffer->size) = '\0';
            @synchronized(self) {
                _html = [[NSString alloc] initWithUTF8String:rendered];
            }

            // Clean up
            free(rendered);
            bufrelease(inputBuffer);
            bufrelease(outputBuffer);
        } else {
            @synchronized(self) {
                _html = @"";
            }
        }
        [NPMNotificationQueue enqueueNotificationWithName:NPMNotificationRenderComplete object:self];

        @synchronized(self) {
            DDLogInfo(@"Render complete");
            _renderInProgress = NO;
            if (_renderNeeded) {
                DDLogInfo(@"Queued render detected");
                _renderNeeded = NO;
                [self render];
            }
        }
    });
}

@end
