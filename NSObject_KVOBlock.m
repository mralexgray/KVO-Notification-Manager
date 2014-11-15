
#import "AtoZ.h"
#import "NSObject_KVOBlock.h"

#import <objc/runtime.h>

@interface CKVOToken : NSObject
@property (readonly,nonatomic,copy)          NSS * keypath;
@property (readonly,nonatomic)                NSI   index;
@property (readonly,nonatomic,copy) KVOFullBlock   block;
@property (readonly,nonatomic,assign)       void * context;

- initWithKeyPath:(NSS*)inKey index:(NSI)inIndex block:(KVOFullBlock)inBlock;
@end

@interface CKVOBlockHelper : NSObject
@property (readonly, nonatomic, weak) id observedObject;
@property (readonly, nonatomic) NSMD *tokensByContext;
@property (readwrite, nonatomic) NSI nextIdentifier;

- initWithObject:inObj;
- (CKVOToken*) insertNewTokenForKeyPath:(NSString *)inKeyPath block:(KVOFullBlock)inBlock;
- (void) removeHandlerForKey:(CKVOToken *)inToken;
- (void) dump;
@end

@implementation NSObject (NSObject_KVOBlock)

- (void) observe:(NSS*)k handler:(IDBlk)watched {

  [self addKVOBlockForKeyPath:k options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionInitial
                                handler:^(NSS *keyPath, id object, NSD *change) {
    watched(object);
  }];
}

- (void) observe:x key:(NSS*)k handler:(void(^)(id observer, id observee))both {

  __block id bSelf = self;
  [x addKVOBlockForKeyPath:k options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
                   handler:^(NSString *keyPath, id object, NSDictionary *change) { both(bSelf, object);
  }];
}

static void *KVO;

- addKVOBlockForKeyPath:(NSS*)inKeyPath options:(NSKeyValueObservingOptions)inOptions handler:(KVOFullBlock)inHandler {
  NSParameterAssert(inHandler);
  NSParameterAssert(inKeyPath);
  NSParameterAssert(NSThread.isMainThread); // TODO -- remove and grow a pair.

  CKVOBlockHelper *theHelper = [self helper:YES];
  NSParameterAssert(theHelper != NULL);

  CKVOToken *theToken = [theHelper insertNewTokenForKeyPath:inKeyPath block:inHandler];
  NSParameterAssert(theToken != NULL);

  void *theContext = theToken.context;
  NSParameterAssert(theContext != NULL);

  [self addObserver:theHelper forKeyPath:inKeyPath options:inOptions context:theContext];

  return theToken;
}

- (void)removeKVOBlockForToken:(CKVOToken*)inToken {
  NSParameterAssert(NSThread.isMainThread); // TODO -- remove and grow a pair.
  CKVOBlockHelper *theHelper = [self helper:NO];
  NSParameterAssert(theHelper != NULL);

  void *theContext = inToken.context;
  NSParameterAssert(theContext);
  NSString *theKeyPath = inToken.keypath;
  NSParameterAssert(theKeyPath.length > 0);
  [self removeObserver:theHelper forKeyPath:theKeyPath context:theContext];

  [theHelper removeHandlerForKey:inToken];
}

- addOneShotKVOBlockForKeyPath:(NSS*)inKeyPath options:(NSKeyValueObservingOptions)inOpts handler:(KVOFullBlock)inHandler {
  __block CKVOToken *theToken = NULL;

  KVOFullBlock theBlock = ^(NSS *keyPath, id object, NSD *change) {
    inHandler(keyPath, object, change);
    [self removeKVOBlockForToken:theToken];
  };

  return theToken = [self addKVOBlockForKeyPath:inKeyPath options:inOpts handler:theBlock];
}

- (CKVOBlockHelper *)helper:(BOOL)inCreate {
  CKVOBlockHelper *theHelper = objc_getAssociatedObject(self, &KVO);
  if (theHelper == NULL && inCreate)
  {
    theHelper = [CKVOBlockHelper.alloc initWithObject:self];
    objc_setAssociatedObject(self, &KVO, theHelper, OBJC_ASSOCIATION_RETAIN);
  }
  return theHelper;
}

- (void) KVODump {

  CKVOBlockHelper *theHelper = [self helper:NO];
  [theHelper dump];
}

- (const char *) UTF8Description { return self.description.UTF8String; }

@end

@implementation CKVOBlockHelper

- initWithObject:inObject { return self = super.init ? _observedObject = inObject, self : nil; }

- (void)dealloc {
  [_tokensByContext enumerateKeysAndObjectsUsingBlock:^(NSNumber *index, CKVOToken *token, BOOL *stop)
   {
     void *theContext = token.context;
     NSParameterAssert(theContext != NULL);
     NSString *theKeypath = token.keypath;
     NSParameterAssert(theKeypath != NULL);
     [_observedObject removeObserver:self forKeyPath:theKeypath context:theContext];
   }];
}

- (NSS*) debugDescription {
  return $(@"%@ (%@, %@, %@)", self.description, self.observedObject, self.tokensByContext, [self.observedObject observationInfo]);
}

- (void)dump {
  printf("*******************************************************\n%s\n", self.UTF8Description);
  printf("\tObserved Object: %p\n", (__bridge void *)self.observedObject);
  printf("\tKeys:\n");
  [_tokensByContext enumerateKeysAndObjectsUsingBlock:^(NSNumber *index, CKVOToken *token, BOOL *stop) {
    printf("\t\t%s\n", index.UTF8Description);
  }];
  printf("\tObservationInfo: %s\n", [[(__bridge id)[self.observedObject observationInfo] description] UTF8String]);
}

- (void)removeHandlerForKey:(CKVOToken *)inToken {

  [_tokensByContext removeObjectForKey:@(inToken.index)];
  if (!_tokensByContext.count) _tokensByContext = NULL;
}

- (CKVOToken*) insertNewTokenForKeyPath:(NSString *)inKeyPath block:(KVOFullBlock)inBlock {

  CKVOToken *theToken = [CKVOToken.alloc initWithKeyPath:inKeyPath index:++self.nextIdentifier block:inBlock];

  _tokensByContext = _tokensByContext ?: @{}.mC;

  return (_tokensByContext[@(theToken.index)] = theToken);
}

- (void) observeValueForKeyPath:(NSS*)keyPath ofObject:object change:(NSD*)change context:(void*)context; {

  NSParameterAssert(context);
  NSNumber *theKey = @((NSInteger)context);

  CKVOToken *theToken= _tokensByContext[theKey];
  theToken ? theToken.block(keyPath, object, change)
           : NSLog(@"Warning: Could not find block for key: %@", theKey);
}

@end

@implementation CKVOToken

- initWithKeyPath:(NSString*)inKey index:(NSInteger)inIndex block:(KVOFullBlock)inBlock {

  SUPERINIT; return _keypath  = inKey, _index = inIndex, _block = inBlock, self;
}

- (NSString *)description { return $(@"%@ (%@ #%ld)", super.description, self.keypath, (unsigned long)self.index); }

- (void*) context { return((void*)self.index); }

@end


/*!  NSObject_KVOBlock.m - TouchCode

 Created by Jonathan Wight on 07/24/11.  Copyright 2011 toxicsoftware.com. All rights reserved.

 Redistribution and use in source and binary forms, with or without modification, are
 permitted provided that the following conditions are met:

 1. Redistributions of source code must retain the above copyright notice, this list of
 conditions and the following disclaimer.

 2. Redistributions in binary form must reproduce the above copyright notice, this list
 of conditions and the following disclaimer in the documentation and/or other materials
 provided with the distribution.

 THIS SOFTWARE IS PROVIDED BY TOXICSOFTWARE.COM ``AS IS'' AND ANY EXPRESS OR IMPLIED
 WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
 FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL TOXICSOFTWARE.COM OR
 CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
 ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

 The views and conclusions contained in the software and documentation are those of the
 authors and should not be interpreted as representing official policies, either expressed
 or implied, of toxicsoftware.com.
 */

