//
//  ProcessCommentComponentsTask.m
//  appledoc
//
//  Created by Tomaz Kragelj on 8/12/12.
//  Copyright (c) 2012 Tomaz Kragelj. All rights reserved.
//

#import "Objects.h"
#import "CommentInfo.h"
#import "CommentComponentInfo.h"
#import "CommentNamedArgumentInfo.h"
#import "ProcessCommentComponentsTask.h"

@interface ProcessCommentComponentsTask ()
@property (nonatomic, strong) NSMutableString *currentComponentBuilder;
@property (nonatomic, strong) NSMutableArray *currentDiscussion;
@end

#pragma mark -

@implementation ProcessCommentComponentsTask

#pragma mark - Processing

- (NSInteger)processComment:(CommentInfo *)comment {
	LogProInfo(@"Processing comment '%@' for components...", [comment.sourceString gb_description]);
	self.currentDiscussion = [@[] mutableCopy];
	[self.markdownParser parseString:comment.sourceString];
	[self registerCommentComponentsFromString:self.currentComponentBuilder];
	if (self.currentDiscussion.count > 0) {
		LogProDebug(@"Registering abstract and discussion...");
		
		// Always take first paragraph as abstract. The rest are either discussion or parameters/exceptions etc.
		CommentComponentInfo *abstract = self.currentDiscussion[0];
		[self.currentDiscussion removeObject:abstract];
		
		// Scan through the components and prepare various sections. Note that once we step into arguments, we take all subsequent components as part of the argument!
		NSMutableArray *discussion = [@[] mutableCopy];
		NSMutableArray *parameters = [@[] mutableCopy];
		NSMutableArray *exceptions = [@[] mutableCopy];
		__block CommentNamedArgumentInfo *currentNamedArgument = nil;
		[self.currentDiscussion enumerateObjectsUsingBlock:^(CommentComponentInfo *component, NSUInteger idx, BOOL *stop) {
			NSString *string = component.sourceString;
			BOOL matched = NO;
			
			// Match @param. Note that we also remove '@param <name>' prefix from source string.
			if (!matched) {
				matched = [[NSRegularExpression gb_paramMatchingRegularExpression] gb_firstMatchIn:string match:^(NSTextCheckingResult *match) {
					NSString *name = [match gb_stringAtIndex:1 in:string];
					LogProDebug(@"Starting @param %@...", name);
					component.sourceString = [match gb_remainingStringIn:string];
					currentNamedArgument = [[CommentNamedArgumentInfo alloc] init];
					currentNamedArgument.argumentName = name;
					[parameters addObject:currentNamedArgument];
				}];
			}
			
			// Match @exception. Note that we also remove '@exception <name>' prefix from source string.
			if (!matched) {
				matched = [[NSRegularExpression gb_exceptionMatchingRegularExpression] gb_firstMatchIn:string match:^(NSTextCheckingResult *match) {
					NSString *name = [match gb_stringAtIndex:1 in:string];
					LogProDebug(@"Starting @exception %@...", name);
					component.sourceString = [match gb_remainingStringIn:string];
					currentNamedArgument = [[CommentNamedArgumentInfo alloc] init];
					currentNamedArgument.argumentName = name;
					[exceptions addObject:currentNamedArgument];
				}];
			}
			
			// Append component to current named argument (@param, @exception etc) if one available.
			if (currentNamedArgument) {
				LogProDebug(@"Appending %@ to argument %@...", [string gb_description], currentNamedArgument.argumentName);
				[currentNamedArgument.argumentComponents addObject:component];
				return;
			}
			
			// Append component to discussion otherwise.
			LogProDebug(@"Appending %@ to discussion...", [string gb_description]);
			[discussion addObject:component];
		}];
		
		[comment setCommentAbstract:abstract];
		if (discussion.count > 0) [comment setCommentDiscussion:discussion];
		if (parameters.count > 0) [comment setCommentParameters:parameters];
		if (exceptions.count > 0) [comment setCommentExceptions:exceptions];
	}
	return GBResultOk;
}

#pragma mark - Comment components handling

- (void)registerCommentComponentsFromString:(NSString *)string {
	if (string.length == 0) return;
	LogProDebug(@"Registering comment component from '%@'...", [string gb_description]);
	
	// Split multiple named arguments (@param, @exception etc.) into separate components. If single or none found, just use the whole string.
	NSArray *matches = [[NSRegularExpression gb_argumentMatchingRegularExpression] gb_allMatchesIn:string];
	if (matches.count > 1 && [matches[0] range].location == 0) {
		__block NSUInteger lastMatchLocation;
		[matches enumerateObjectsUsingBlock:^(NSTextCheckingResult *match, NSUInteger idx, BOOL *stop) {
			if (idx == 0) return;
			NSUInteger previousMatchLocation = [matches[idx-1] range].location;
			lastMatchLocation = match.range.location;
			NSRange range = NSMakeRange(previousMatchLocation, lastMatchLocation - previousMatchLocation);
			NSString *componentString = [[string substringWithRange:range] gb_stringByTrimmingWhitespaceAndNewLine];
			CommentComponentInfo *component = [self componentInfoFromString:componentString];
			[self.currentDiscussion addObject:component];
		}];
		NSString *lastString = [string substringFromIndex:lastMatchLocation];
		CommentComponentInfo *component = [self componentInfoFromString:lastString];
		[self.currentDiscussion addObject:component];
	} else {
		CommentComponentInfo *component = [self componentInfoFromString:string];
		[self.currentDiscussion addObject:component];
	}
}

#pragma mark - Low level string parsing

- (CommentComponentInfo *)componentInfoFromString:(NSString *)string {
	LogProDebug(@"Creating component for %@...", string);
	CommentComponentInfo *result = [[CommentComponentInfo alloc] init];
	result.sourceString = string;
	return result;
}

@end

#pragma mark -

@implementation ProcessCommentComponentsTask (MarkdownParserDelegateImplementation)

- (void)markdownParser:(MarkdownParser *)parser parseBlockCode:(const struct buf *)text language:(const struct buf *)language output:(struct buf *)buffer {
	LogProDebug(@"Processing block code '%@'...", [[self stringFromBuffer:text] gb_description]);
}

- (void)markdownParser:(MarkdownParser *)parser parseBlockQuote:(const struct buf *)text output:(struct buf *)buffer {
	LogProDebug(@"Processing block quote '%@'...", [[self stringFromBuffer:text] gb_description]);
}

- (void)markdownParser:(MarkdownParser *)parser parseBlockHTML:(const struct buf *)text output:(struct buf *)buffer {
	LogProDebug(@"Processing block HTML '%@'...", [[self stringFromBuffer:text] gb_description]);
}

- (void)markdownParser:(MarkdownParser *)parser parseHeader:(const struct buf *)text level:(NSInteger)level output:(struct buf *)buffer {
	LogProDebug(@"Processing header '%@'...", [[self stringFromBuffer:text] gb_description]);
}

- (void)markdownParser:(MarkdownParser *)parser parseHRule:(struct buf *)buffer {
	LogProDebug(@"Processing hrule...");
}

- (void)markdownParser:(MarkdownParser *)parser parseList:(const struct buf *)text flags:(NSInteger)flags output:(struct buf *)buffer {
	LogProDebug(@"Processing list '%@'...", [[self stringFromBuffer:text] gb_description]);
}

- (void)markdownParser:(MarkdownParser *)parser parseListItem:(const struct buf *)text flags:(NSInteger)flags output:(struct buf *)buffer {
	LogProDebug(@"Processing list item '%@'...", [[self stringFromBuffer:text] gb_description]);
}

- (void)markdownParser:(MarkdownParser *)parser parseParagraph:(const struct buf *)text output:(struct buf *)buffer {
	NSString *paragraph = [self stringFromBuffer:text];
	LogProDebug(@"Detected paragraph '%@'.", [paragraph gb_description]);
	if (self.currentComponentBuilder) [self registerCommentComponentsFromString:self.currentComponentBuilder];
	self.currentComponentBuilder = [paragraph mutableCopy];
}

- (void)markdownParser:(MarkdownParser *)parser parseTableHeader:(const struct buf *)header body:(const struct buf *)body output:(struct buf *)buffer {
}

- (void)markdownParser:(MarkdownParser *)parser parseTableRow:(const struct buf *)text output:(struct buf *)buffer {
}

- (void)markdownParser:(MarkdownParser *)parser parseTableCell:(const struct buf *)text flags:(NSInteger)flags output:(struct buf *)buffer {
}

@end