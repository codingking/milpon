//
//  DBTasktProvider.h
//  Milpon
//
//  Created by mootoh on 3/05/09.
//  Copyright 2009 deadbeaf.org. All rights reserved.
//

#import "TaskProvider.h"

@class LocalCache;

@interface DBTaskProvider : TaskProvider
{
   LocalCache *local_cache_;
}

//- (void) createNoteAtOnline:(NSString *)note title:(NSString *)title task_id:(NSNumber *)tid;

@end // DBTaskProvider