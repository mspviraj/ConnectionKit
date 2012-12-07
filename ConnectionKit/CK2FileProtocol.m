//
//  CK2FileProtocol.m
//  Connection
//
//  Created by Mike on 18/10/2012.
//
//

#import "CK2FileProtocol.h"
#import "CK2FTPProtocol.h"

@implementation CK2FileProtocol

+ (BOOL)canHandleURL:(NSURL *)url;
{
    return [url isFileURL];
}

- (id)initWithBlock:(void (^)(void))block;
{
    if (self = [self init])
    {
        NSAssert(block != nil, @"should have a valid block");
        _block = [block copy];
    }
    
    return self;
}

- (void)dealloc
{
    [_block release];
    [super dealloc];
}

- (id)initForEnumeratingDirectoryWithRequest:(NSURLRequest *)request includingPropertiesForKeys:(NSArray *)keys options:(NSDirectoryEnumerationOptions)mask client:(id<CK2ProtocolClient>)client;
{
    return [self initWithBlock:^{
        
        // Enumerate contents
        NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtURL:[request URL]
                                                                 includingPropertiesForKeys:keys
                                                                                    options:mask
                                                                               errorHandler:^BOOL(NSURL *url, NSError *error) {
            
                                                                                   NSLog(@"enumeration error: %@", error);
                                                                                   return YES;
                                                                               }];
                
        BOOL reportedDirectory = NO;
        
        NSURL *aURL;
        while (aURL = [enumerator nextObject])
        {
            // Report the main directory first
            if (!reportedDirectory)
            {
                [client protocol:self didDiscoverItemAtURL:[request URL]];
                reportedDirectory = YES;
            }
            
            [client protocol:self didDiscoverItemAtURL:aURL];
        }
                
        [client protocolDidFinish:self];
    }];
}

- (id)initForCreatingDirectoryWithRequest:(NSURLRequest *)request withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes client:(id<CK2ProtocolClient>)client;
{
    return [self initWithBlock:^{
        
        NSError *error;
        if ([[NSFileManager defaultManager] createDirectoryAtURL:[request URL] withIntermediateDirectories:createIntermediates attributes:attributes error:&error])
        {
            [client protocolDidFinish:self];
        }
        else
        {
            [client protocol:self didFailWithError:error];
        }
    }];
}

#define USE_CURL_HANDLE_FOR_FILE_CREATION 1
#if USE_CURL_HANDLE_FOR_FILE_CREATION

- (id)initForCreatingFileWithRequest:(NSURLRequest *)request withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes client:(id<CK2ProtocolClient>)client progressBlock:(void (^)(NSUInteger))progressBlock;
{
    id result =  nil;
    [self release];
    self = nil;

    CK2FTPProtocol* curlProtocol = [[CK2FTPProtocol alloc] initForCreatingFileWithRequest:request withIntermediateDirectories:createIntermediates openingAttributes:attributes client:client progressBlock:progressBlock];
    if (curlProtocol)
    {
        result = curlProtocol;
    }

    return result;
}

#else

- (id)initForCreatingFileWithRequest:(NSURLRequest *)request withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes client:(id<CK2ProtocolClient>)client progressBlock:(void (^)(NSUInteger))progressBlock;
{
    return [self initWithBlock:^{

        if (createIntermediates)
        {
            NSError *error;
            NSURL* intermediates = [[request URL] URLByDeletingLastPathComponent];
            if (![[NSFileManager defaultManager] createDirectoryAtURL:intermediates withIntermediateDirectories:YES attributes:nil error:&error])
            {
                [client protocol:self didFailWithError:error];
                return;
            }
        }
        
        NSData *data = [request HTTPBody];
        if (data)
        {
            // TODO: Use a stream or similar to write incrementally and report progress
            NSError *error;
            if ([data writeToURL:[request URL] options:0 error:&error])
            {
                [client protocolDidFinish:self];
            }
            else
            {
                [client protocol:self didFailWithError:error];
            }
        }
        else
        {
            // TODO: Work asynchronously so aren't blocking this one throughout the write
            NSInputStream *inputStream = [request HTTPBodyStream];
            [inputStream open];
            
            NSOutputStream *outputStream = [[NSOutputStream alloc] initWithURL:[request URL] append:NO];
            [outputStream open];
            // TODO: Handle outputStream being nil?
            
            uint8_t buffer[1024];
            while ([inputStream hasBytesAvailable])
            {
                NSInteger length = [inputStream read:buffer maxLength:1024];
                if (length < 0)
                {
                    [client protocol:self didFailWithError:[inputStream streamError]];
                    return;
                }

                NSUInteger written = [outputStream write:buffer maxLength:length];
                if (written != length)
                {
                    [client protocol:self didFailWithError:[outputStream streamError]];
                    return;
                }

                if (progressBlock)
                {
                    progressBlock(length);
                }
            }
            
            [inputStream close];
            [outputStream close];
            [outputStream release];
            
            [client protocolDidFinish:self];
        }
    }];
}

#endif

- (id)initForRemovingFileWithRequest:(NSURLRequest *)request client:(id<CK2ProtocolClient>)client;
{
    return [self initWithBlock:^{
                
        NSError *error;
        if ([[NSFileManager defaultManager] removeItemAtURL:[request URL] error:&error])
        {
            [client protocolDidFinish:self];
        }
        else
        {
            [client protocol:self didFailWithError:error];
        }
    }];
}

- (id)initForSettingAttributes:(NSDictionary *)keyedValues ofItemWithRequest:(NSURLRequest *)request client:(id<CK2ProtocolClient>)client;
{
    return [self initWithBlock:^{
        
        NSError *error;
        if ([[NSFileManager defaultManager] setAttributes:keyedValues ofItemAtPath:[[request URL] path] error:&error])
        {
            [client protocolDidFinish:self];
        }
        else
        {
            [client protocol:self didFailWithError:error];
        }
    }];
}

- (void)start;
{
    _block();
}

@end
