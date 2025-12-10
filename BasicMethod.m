/**
 *  @file BasicMethod.m
 * HttpClient
 *
 *  Copyright (c) 2010 Scott Slaugh, Brigham Young University
 *  Copyright (c) 2012 Lolay, Inc.
 *   
 *  Permission is hereby granted, free of charge, to any person obtaining a copy
 *  of this software and associated documentation files (the "Software"), to deal
 *  in the Software without restriction, including without limitation the rights
 *  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 *  copies of the Software, and to permit persons to whom the Software is
 *  furnished to do so, subject to the following conditions:
 *  
 *  The above copyright notice and this permission notice shall be included in
 *  all copies or substantial portions of the Software.
 *   
 *  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 *  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 *  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 *  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 *  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 *  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 *  THE SOFTWARE.
 *
 */

#import "BasicMethod.h"
#import "Constants.h"
#import "DelegateMessenger.h"
#import "LolayHttpClientGlobals.h"

@interface BasicMethod()

@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) NSURLSessionDataTask *task;
@property(nonatomic, assign) NSUInteger tryCount;
@property(nonatomic, strong) NSDate *lastAttemptTime;
@property(nonatomic, strong) NSDate *initialAttemptTime;
@property(nonatomic, assign) NSTimeInterval maxTimeToTry;

@end

@implementation BasicMethod

- (id)init {
	self = [super init];
	
	if (self != nil) {
		//Initialize the dictionary used for storing parameters
		params = [[NSMutableDictionary alloc] init];
		headers = [[NSMutableDictionary alloc] init];
		timeoutInSeconds = 60; // DEFAULT
        cachePolicy = NSURLRequestUseProtocolCachePolicy; // Default cache policy
		handleCookies = YES;
		encodeParameterNames = YES;
	}
	
	return self;
}

- (void)setTimeout:(int)timeoutValue {
	timeoutInSeconds = timeoutValue;
}

- (int)timeout {
    return timeoutInSeconds;
}

- (void)setCachePolicy:(NSURLRequestCachePolicy) cachePolicyValue {
    cachePolicy = cachePolicyValue;
}

- (void) setHandleCookies:(BOOL)shouldHandleCookies
{
	handleCookies = shouldHandleCookies;
}

- (void) setEncodeParameterNames:(BOOL) encodeParameterNamesIn {
	encodeParameterNames = encodeParameterNamesIn;
}

- (NSDictionary*) parameters {
    return params;
}

- (NSData*) body {
	return body;
}

- (NSString*) bodyString {
	return [[NSString alloc] initWithData:body encoding:encoding];
}

- (void)addParameter:(NSString*)paramData withName:(NSString*)paramName {
	//Add the parameter to the parameters dictionary
	id existingValue = [params valueForKey:paramName];
	if (existingValue != nil) {
		if ([existingValue isKindOfClass:[NSMutableArray class]]) {
			[(NSMutableArray*)existingValue addObject:paramData];
		} else {
			NSMutableArray* newValue = [[NSMutableArray alloc] init];
			[newValue addObject:existingValue];
			[newValue addObject:paramData];
			[params setValue:newValue forKey:paramName];
		}
	} else {
		[params setValue:paramData forKey:paramName];
	}
}

- (void)addParametersFromDictionary:(NSDictionary*)dict {
	for (id key in dict) {
		[params setValue:[dict objectForKey:key] forKey:key];
	}
}

- (NSDictionary*) headers {
    return headers;
}

- (void)addHeader:(NSString*)headerData withName:(NSString*)headerName {
	//Add the header to the headers dictionary
	[headers setValue:headerData forKey:headerName];
}

- (NSString*) encodeUrl:(NSString*) string {
	if (string == nil) {
		return nil;
	}
	
    NSString *newString = [string stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];
    newString = [[newString stringByReplacingOccurrencesOfString:@" " withString:@"+"] stringByReplacingOccurrencesOfString:@"&" withString:@"%26"];
    
    if (newString) {
        return newString;
    }
    return @"";
}

- (void)prepareMethod:(NSURL*)methodURL methodType:(NSString*)methodType dataInBody:(bool)dataInBody contentType:(NSString*)contentType withRequest:(NSMutableURLRequest*)request {
  //Set the destination URL
  [request setURL:methodURL];
  //Set the method type
  [request setHTTPMethod:methodType];

  if([headers objectForKey:@"Content-Type"] == nil) {
    [request addValue:contentType forHTTPHeaderField:@"Content-Type"];
  }
  //Set the timeout
  [request setTimeoutInterval:timeoutInSeconds];
  //Gzip header
  if([headers objectForKey:@"Accept-Encoding"] == nil) {
    [request addValue:@"gzip" forHTTPHeaderField:@"Accept-Encoding"];
  }

  //Create a data object to hold the body while we're creating it
  if (! body) {
    NSMutableData * bodyData = [[NSMutableData alloc] init];

    static NSDateFormatter *isoFormatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      isoFormatter = [[NSDateFormatter alloc] init];
      [isoFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss'Z'"];
      [isoFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    });

    int cCount = 0;
    for (NSString* cKey in params) {
      cCount++;
      if (cCount > 1) {
        [bodyData appendData:[@"&" dataUsingEncoding:encoding]];
      }

      id value = [params valueForKey:cKey];
      NSString* encodedKey = encodeParameterNames ? [self encodeUrl:cKey] : cKey;

      if ([value isKindOfClass:[NSArray class]] || [value isKindOfClass:[NSMutableArray class]]) {

        // --- THIS IS THE FIX ---
        // Create the special key for arrays: "key[]"
        NSString *arrayKey = [NSString stringWithFormat:@"%@[]", encodedKey];

        int pCount = 0;
        for (id arrayValue in (NSArray *)value) {
          pCount++;
          if (pCount > 1) {
            [bodyData appendData:[@"&" dataUsingEncoding:encoding]];
          }

          // Convert the item (which could be string, number) to a string
          NSString *stringValue;
          if ([arrayValue isKindOfClass:[NSString class]]) {
            stringValue = (NSString *)arrayValue;
          } else if ([arrayValue isKindOfClass:[NSNumber class]]) {
            stringValue = [arrayValue stringValue];
          } else {
            stringValue = [NSString stringWithFormat:@"%@", arrayValue];
          }

          // Send as: key[]=val1&key[]=val2
          [bodyData appendData:[[NSString stringWithFormat:@"%@=%@", arrayKey, [self encodeUrl:stringValue]] dataUsingEncoding:encoding]];
        }

      } else {
        // --- THIS IS CORRECT ---
        // (Handles NSNumber, NSDate, NSString)
        NSString *stringValue;

        if ([value isKindOfClass:[NSString class]]) {
          stringValue = (NSString *)value;
        } else if ([value isKindOfClass:[NSNumber class]]) {
          // Booleans/Numbers are sent as "1", "0", "123"
          // This is the standard.
          stringValue = [value stringValue];
        } else if ([value isKindOfClass:[NSDate class]]) {
          stringValue = [isoFormatter stringFromDate:(NSDate *)value];
        } else if ([value isEqual:[NSNull null]]) {
          stringValue = @"";
        } else {
          // Fallback for any other type (prevents crash)
          stringValue = [NSString stringWithFormat:@"%@", value];
        }

        [bodyData appendData:[[NSString stringWithFormat:@"%@=%@", encodedKey, [self encodeUrl:stringValue]] dataUsingEncoding:encoding]];
      }
    }
    body = bodyData;
  }

  //Loop over the items in the headers dictionary and add them to the request
  for (NSString* cHeaderKey in headers) {
    [request addValue:[headers valueForKey:cHeaderKey] forHTTPHeaderField:cHeaderKey];
  }

  //Add the body data in either the actual HTTP body or as part of the URL query
  if (dataInBody || [body length] > 0) {
    if ([methodType isEqualToString:@"POST"]|| [methodType isEqualToString:@"PUT"]) {
      [request setHTTPBody:body];
    } else if ([methodType isEqualToString:@"GET"]|| [methodType isEqualToString:@"DELETE"] ) {
      NSMutableString * newURLString = [[NSMutableString alloc] initWithString:[methodURL absoluteString]];
      NSString * bodyString = [[NSString alloc] initWithData:body encoding:encoding];
      [newURLString appendFormat:@"?%@", bodyString];
      NSURL * newURL = [NSURL URLWithString:newURLString];
      [request setURL:newURL];
    }
  }
}

//- (HttpResponse*)executeMethodSynchronously:(NSURL*)methodURL methodType:(NSString*)methodType dataInBody:(bool)dataInBody contentType:(NSString*)contentType error:(NSError**) error {
//    
//    //Create a new URL request object
//    NSMutableURLRequest * request = [[NSMutableURLRequest alloc] init];
//    
//    self.tryCount++;
//    request.timeoutInterval = timeoutInSeconds;
//
//    self.lastAttemptTime = [NSDate date];
//    
//    if (self.initialAttemptTime == nil) {
//        self.initialAttemptTime = [NSDate date];
//    }
//    
//    if(cachePolicy != NSURLRequestUseProtocolCachePolicy) {
//        [request setCachePolicy:cachePolicy];
//    }
//    
//    [request setHTTPShouldHandleCookies: handleCookies];
//    
//    [self prepareMethod:methodURL methodType:methodType dataInBody:dataInBody contentType:contentType withRequest:request];
//    
//    NSString* requestBody = [self bodyString];
//    DLog(@"Request url=%@, headers=%@, parameters=%@, body=%@", [request URL], [self headers], [self parameters], requestBody.length < 4096 ? requestBody : [NSString stringWithFormat:@"(length=%lu)", (unsigned long) requestBody.length]);
//
//    //Execute the HTTP method, saving the return data
//    NSHTTPURLResponse * response;
//    NSError* errorResponse = nil;
//    NSData *returnData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&errorResponse];
//    HttpResponse * responseObject = [[HttpResponse alloc] initWithHttpURLResponse:response withData:returnData];
//    
//    if (errorResponse) {
//        DLog(@"Error url=%@, error=%@", [request URL], errorResponse);
//        if (error != NULL) {
//            *error = errorResponse;
//        }
//    }
//    
//    DLog(@"Response url=%@, status=%li, headers=%@, body=%@", [request URL], (long) [responseObject statusCode], [responseObject headerFields], [responseObject responseString]);
//    
//    return responseObject;
//}

- (void)executeMethodAsynchronously:(NSURL*)methodURL methodType:(NSString*)methodType dataInBody:(bool)dataInBody contentType:(NSString*)contentType withHandler:(MethodHandler)methodHandler {
	NSMutableURLRequest * request = [[NSMutableURLRequest alloc] init];
	
    request.timeoutInterval = timeoutInSeconds;
    
    self.tryCount++;
    self.lastAttemptTime = [NSDate date];
    
    if (self.initialAttemptTime == nil) {
        self.initialAttemptTime = [NSDate date];
    }
    
	[self prepareMethod:methodURL methodType:methodType dataInBody:dataInBody contentType:contentType withRequest:request];

	NSString* requestBody = [self bodyString];
	DLog(@"Request url=%@, headers=%@, parameters=%@, body=%@", [request URL], [self headers], [self parameters], requestBody.length < 4096 ? requestBody : [NSString stringWithFormat:@"(length=%lu)", (unsigned long) requestBody.length]);

	//Execute the HTTP method
	//DelegateMessenger * messenger = [DelegateMessenger delegateMessengerWithDelegate:delegate];
	
	//[NSURLConnection connectionWithRequest:request delegate:messenger];

    __weak BasicMethod *method = self;
    
    if (!self.cancelled) {
    self.session = [NSURLSession sharedSession];
    
    self.task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        
        // make sure to not call back if we were cancelled during our task.
        if (methodHandler != nil && !method.cancelled) {
            methodHandler(data, response, error);
        }
        
    }];
    
    [self.task resume];
    }
}

-(void) cancel {
    [self.task cancel];
    self.session = nil;
    self.task = nil;
    self.cancelled = YES;
    self.lastAttemptTime = nil;
}

@end
