#import <SenTestingKit/SenTestingKit.h>

#import "YapDatabase.h"
#import "TestObject.h"

#import "DDLog.h"
#import "DDTTYLogger.h"

#import <libkern/OSAtomic.h>

@interface TestYapDatabase : SenTestCase
@end

@implementation TestYapDatabase

- (NSString *)databasePath:(NSString *)suffix
{
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
	NSString *baseDir = ([paths count] > 0) ? [paths objectAtIndex:0] : NSTemporaryDirectory();
	
	NSString *databaseName = [NSString stringWithFormat:@"%@-%@.sqlite", THIS_FILE, suffix];
	
	return [baseDir stringByAppendingPathComponent:databaseName];
}

- (void)setUp
{
	[super setUp];
	[DDLog removeAllLoggers];
	[DDLog addLogger:[DDTTYLogger sharedInstance]];
}

- (void)tearDown
{
	[DDLog flushLog];
	[super tearDown];
}

- (void)test1
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	STAssertNotNil(database, @"Oops");
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
	TestObject *object = [TestObject generateTestObject];
	TestObjectMetadata *metadata = [object extractMetadata];
	
	NSString *key1 = @"some-key-1";
	NSString *key2 = @"some-key-2";
	NSString *key3 = @"some-key-3";
	NSString *key4 = @"some-key-4";
	NSString *key5 = @"some-key-5";
	
	__block id aObj;
	__block id aMetadata;
	__block BOOL result;
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		STAssertTrue([transaction numberOfCollections] == 0, @"Expected zero collection count");
		STAssertTrue([[transaction allCollections] count] == 0, @"Expected empty array");
		
		STAssertTrue([transaction numberOfKeysInCollection:nil] == 0, @"Expected zero key count");
		
		STAssertNil([transaction objectForKey:@"non-existant" inCollection:nil], @"Expected nil object");
		STAssertNil([transaction primitiveDataForKey:@"non-existant" inCollection:nil], @"Expected nil data");
		
		STAssertFalse([transaction hasObjectForKey:@"non-existant" inCollection:nil], @"Expected NO object for key");
		
		BOOL result = [transaction getObject:&aObj metadata:&aMetadata forKey:@"non-existant" inCollection:nil];
		
		STAssertFalse(result, @"Expected NO getObject for key");
		STAssertNil(aObj, @"Expected object to be set to nil");
		STAssertNil(aMetadata, @"Expected metadata to be set to nil");
		
		STAssertNil([transaction metadataForKey:@"non-existant" inCollection:nil], @"Expected nil metadata");
		
		STAssertNoThrow([transaction removeObjectForKey:@"non-existant" inCollection:nil], @"Expected no issues");
		
		NSArray *keys = @[@"non",@"existant",@"keys"];
		STAssertNoThrow([transaction removeObjectsForKeys:keys inCollection:nil], @"Expected no issues");
		
		__block NSUInteger count = 0;
		
		[transaction enumerateKeysAndMetadataInCollection:nil usingBlock:^(NSString *key, id metadata, BOOL *stop){
			count++;
		}];
		
		STAssertTrue(count == 0, @"Expceted zero keys");
		
		[transaction enumerateKeysAndObjectsInCollection:nil
		                                      usingBlock:^(NSString *key, id object, BOOL *stop){
			count++;
		}];
		
		STAssertTrue(count == 0, @"Expceted zero keys");												
														
		// Attempt to set metadata for a key that has no associated object.
		// It should silently fail (do nothing).
		// And further queries to fetch metadata for the same key should return nil.
		
		STAssertNoThrow([transaction setMetadata:metadata forKey:@"non-existant" inCollection:nil],
		                 @"Expected nothing to happen");
		
		STAssertNil([transaction metadataForKey:@"non-existant" inCollection:nil],
		            @"Expected nil metadata since no object");
	}];
	
	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test object without metadata
		
		[transaction setObject:object forKey:key1 inCollection:nil];
		
		STAssertTrue([transaction numberOfKeysInCollection:nil] == 1, @"Expected 1 key");
		STAssertTrue([[transaction allKeysInCollection:nil] count] == 1, @"Expected 1 key");
		
		STAssertTrue([transaction numberOfKeysInCollection:@""] == 1, @"Expected 1 key");
		STAssertTrue([[transaction allKeysInCollection:@""] count] == 1, @"Expected 1 key");
		
		STAssertNotNil([transaction objectForKey:key1 inCollection:nil], @"Expected non-nil object");
		STAssertNotNil([transaction primitiveDataForKey:key1 inCollection:nil], @"Expected non-nil data");
		
		STAssertTrue([transaction hasObjectForKey:key1 inCollection:nil], @"Expected YES");
		
		result = [transaction getObject:&aObj metadata:&aMetadata forKey:key1 inCollection:nil];
		
		STAssertTrue(result, @"Expected YES");
		STAssertNotNil(aObj, @"Expected non-nil object");
		STAssertNil(aMetadata, @"Expected nil metadata");
		
		STAssertNil([transaction metadataForKey:key1 inCollection:nil], @"Expected nil metadata");
		
		[transaction enumerateKeysAndMetadataInCollection:nil usingBlock:^(NSString *key, id metadata, BOOL *stop){
			
			STAssertNil(metadata, @"Expected nil metadata");
		}];
		
		[transaction enumerateKeysAndObjectsInCollection:nil
		                                      usingBlock:^(NSString *key, id object, BOOL *stop){
			
			STAssertNotNil(aObj, @"Expected non-nil object");
		}];
		
		[transaction enumerateRowsInCollection:nil
		                            usingBlock:^(NSString *key, id object, id metadata, BOOL *stop){
			
			STAssertNotNil(aObj, @"Expected non-nil object");
			STAssertNil(metadata, @"Expected nil metadata");
		}];
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test remove object
		
		[transaction removeObjectForKey:key1 inCollection:nil];
		
		STAssertTrue([transaction numberOfKeysInCollection:nil] == 0, @"Expected 0 keys");
		STAssertTrue([[transaction allKeysInCollection:nil] count] == 0, @"Expected 0 keys");
		
		STAssertNil([transaction objectForKey:key1 inCollection:nil], @"Expected nil object");
		STAssertNil([transaction primitiveDataForKey:key1 inCollection:nil], @"Expected nil data");
		
		STAssertFalse([transaction hasObjectForKey:key1 inCollection:nil], @"Expected NO");
	}];
	
	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test object with metadata
		
		[transaction setObject:object forKey:key1 inCollection:nil withMetadata:metadata];
		
		STAssertTrue([transaction numberOfKeysInCollection:nil] == 1, @"Expected 1 key");
		STAssertTrue([[transaction allKeysInCollection:nil] count] == 1, @"Expected 1 key");
		
		STAssertNotNil([transaction objectForKey:key1 inCollection:nil], @"Expected non-nil object");
		STAssertNotNil([transaction primitiveDataForKey:key1 inCollection:nil], @"Expected non-nil data");
		
		STAssertTrue([transaction hasObjectForKey:key1 inCollection:nil], @"Expected YES");
		
		result = [transaction getObject:&aObj metadata:&aMetadata forKey:key1 inCollection:nil];
		
		STAssertTrue(result, @"Expected YES");
		STAssertNotNil(aObj, @"Expected non-nil object");
		STAssertNotNil(aMetadata, @"Expected non-nil metadata");
		
		STAssertNotNil([transaction metadataForKey:key1 inCollection:nil], @"Expected non-nil metadata");
		
		[transaction enumerateKeysAndMetadataInCollection:nil usingBlock:^(NSString *key, id metadata, BOOL *stop){
			
			STAssertNotNil(metadata, @"Expected non-nil metadata");
		}];
		
		[transaction enumerateKeysAndObjectsInCollection:nil
		                                      usingBlock:^(NSString *key, id object, BOOL *stop){
			
			STAssertNotNil(aObj, @"Expected non-nil object");
		}];
		
		[transaction enumerateRowsInCollection:nil
		                            usingBlock:^(NSString *key, id object, id metadata, BOOL *stop){
			
			STAssertNotNil(aObj, @"Expected non-nil object");
			STAssertNotNil(metadata, @"Expected non-nil metadata");
		}];
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test multiple objects
		
		[transaction setObject:object forKey:key1 inCollection:nil withMetadata:metadata];
		[transaction setObject:object forKey:key2 inCollection:nil withMetadata:metadata];
		[transaction setObject:object forKey:key3 inCollection:nil withMetadata:metadata];
		[transaction setObject:object forKey:key4 inCollection:nil withMetadata:metadata];
		[transaction setObject:object forKey:key5 inCollection:nil withMetadata:metadata];
		
		[transaction setObject:object forKey:key1 inCollection:@"test" withMetadata:metadata];
		[transaction setObject:object forKey:key2 inCollection:@"test" withMetadata:metadata];
		[transaction setObject:object forKey:key3 inCollection:@"test" withMetadata:metadata];
		[transaction setObject:object forKey:key4 inCollection:@"test" withMetadata:metadata];
		[transaction setObject:object forKey:key5 inCollection:@"test" withMetadata:metadata];
		
		STAssertTrue([transaction numberOfKeysInCollection:nil] == 5, @"Expected 5 keys");
		STAssertTrue([[transaction allKeysInCollection:nil] count] == 5, @"Expected 5 keys");
		
		STAssertTrue([transaction numberOfKeysInCollection:@"test"] == 5, @"Expected 5 keys");
		STAssertTrue([[transaction allKeysInCollection:@"test"] count] == 5, @"Expected 5 keys");
		
		STAssertTrue([transaction numberOfKeysInAllCollections] == 10, @"Expected 10 keys");
		
		STAssertNotNil([transaction objectForKey:key1 inCollection:nil], @"Expected non-nil object");
		STAssertNotNil([transaction objectForKey:key1 inCollection:@"test"], @"Expected non-nil object");
		
		STAssertTrue([transaction hasObjectForKey:key1 inCollection:nil], @"Expected YES");
		STAssertTrue([transaction hasObjectForKey:key1 inCollection:@"test"], @"Expected YES");
		
		STAssertNotNil([transaction metadataForKey:key1 inCollection:nil], @"Expected non-nil metadata");
		STAssertNotNil([transaction metadataForKey:key1 inCollection:@"test"], @"Expected non-nil metadata");
	}];
	
	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test remove multiple objects
		
		[transaction removeObjectsForKeys:@[ key1, key2, key3 ] inCollection:nil];
		[transaction removeObjectsForKeys:@[ key1, key2, key3 ] inCollection:@"test"];
		
		STAssertTrue([transaction numberOfKeysInCollection:nil] == 2, @"Expected 2 keys");
		STAssertTrue([[transaction allKeysInCollection:nil] count] == 2, @"Expected 2 keys");
		
		STAssertTrue([transaction numberOfKeysInCollection:@"test"] == 2, @"Expected 2 keys");
		STAssertTrue([[transaction allKeysInCollection:@"test"] count] == 2, @"Expected 2 keys");
		
		STAssertTrue([transaction numberOfKeysInAllCollections] == 4, @"Expected 4 keys");
		
		STAssertNil([transaction objectForKey:key1 inCollection:nil], @"Expected nil object");
		STAssertNil([transaction objectForKey:key1 inCollection:@"test"], @"Expected nil object");
		
		STAssertNotNil([transaction objectForKey:key5 inCollection:nil], @"Expected non-nil object");
		STAssertNotNil([transaction objectForKey:key5 inCollection:@"test"], @"Expected non-nil object");
		
		STAssertFalse([transaction hasObjectForKey:key1 inCollection:nil], @"Expected NO");
		STAssertFalse([transaction hasObjectForKey:key1 inCollection:nil], @"Expected NO");

		STAssertTrue([transaction hasObjectForKey:key5 inCollection:nil], @"Expected YES");
		STAssertTrue([transaction hasObjectForKey:key5 inCollection:@"test"], @"Expected YES");
		
		STAssertNil([transaction metadataForKey:key1 inCollection:nil], @"Expected nil metadata");
		STAssertNil([transaction metadataForKey:key1 inCollection:@"test"], @"Expected nil metadata");
		
		STAssertNotNil([transaction metadataForKey:key5 inCollection:nil], @"Expected non-nil metadata");
		STAssertNotNil([transaction metadataForKey:key5 inCollection:@"test"], @"Expected non-nil metadata");
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test remove all objects
		
		[transaction removeAllObjectsInAllCollections];
		
		STAssertNil([transaction objectForKey:key1 inCollection:nil], @"Expected nil object");
		STAssertNil([transaction objectForKey:key1 inCollection:@"test"], @"Expected nil object");
		
		STAssertFalse([transaction hasObjectForKey:key1 inCollection:nil], @"Expected NO");
		STAssertFalse([transaction hasObjectForKey:key1 inCollection:@"test"], @"Expected NO");
		
		STAssertNil([transaction metadataForKey:key1 inCollection:nil], @"Expected nil metadata");
		STAssertNil([transaction metadataForKey:key1 inCollection:@"test"], @"Expected nil metadata");
	}];
	
	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test add objects to a particular collection
		
		[transaction setObject:object forKey:key1 inCollection:nil];
		[transaction setObject:object forKey:key2 inCollection:nil];
		[transaction setObject:object forKey:key3 inCollection:nil];
		[transaction setObject:object forKey:key4 inCollection:nil];
		[transaction setObject:object forKey:key5 inCollection:nil];
		
		[transaction setObject:object forKey:key1 inCollection:@"collection1"];
		[transaction setObject:object forKey:key2 inCollection:@"collection1"];
		[transaction setObject:object forKey:key3 inCollection:@"collection1"];
		[transaction setObject:object forKey:key4 inCollection:@"collection1"];
		[transaction setObject:object forKey:key5 inCollection:@"collection1"];
		
		[transaction setObject:object forKey:key1 inCollection:@"collection2"];
		[transaction setObject:object forKey:key2 inCollection:@"collection2"];
		[transaction setObject:object forKey:key3 inCollection:@"collection2"];
		[transaction setObject:object forKey:key4 inCollection:@"collection2"];
		[transaction setObject:object forKey:key5 inCollection:@"collection2"];
		
		STAssertTrue([transaction numberOfCollections] == 3,
					   @"Incorrect number of collections. Got=%d, Expected=3", [transaction numberOfCollections]);
		
		STAssertTrue([transaction numberOfKeysInCollection:nil] == 5, @"Oops");
		STAssertTrue([transaction numberOfKeysInCollection:@"collection1"] == 5, @"Oops");
		STAssertTrue([transaction numberOfKeysInCollection:@"collection2"] ==  5, @"Oops");
		
		STAssertNotNil([transaction objectForKey:key1 inCollection:nil], @"Oops");
		STAssertNotNil([transaction objectForKey:key2 inCollection:nil], @"Oops");
		STAssertNotNil([transaction objectForKey:key3 inCollection:nil], @"Oops");
		STAssertNotNil([transaction objectForKey:key4 inCollection:nil], @"Oops");
		STAssertNotNil([transaction objectForKey:key5 inCollection:nil], @"Oops");
		
		STAssertNotNil([transaction objectForKey:key1 inCollection:@"collection1"], @"Oops");
		STAssertNotNil([transaction objectForKey:key2 inCollection:@"collection1"], @"Oops");
		STAssertNotNil([transaction objectForKey:key3 inCollection:@"collection1"], @"Oops");
		STAssertNotNil([transaction objectForKey:key4 inCollection:@"collection1"], @"Oops");
		STAssertNotNil([transaction objectForKey:key5 inCollection:@"collection1"], @"Oops");
		
		STAssertNotNil([transaction objectForKey:key1 inCollection:@"collection2"], @"Oops");
		STAssertNotNil([transaction objectForKey:key2 inCollection:@"collection2"], @"Oops");
		STAssertNotNil([transaction objectForKey:key3 inCollection:@"collection2"], @"Oops");
		STAssertNotNil([transaction objectForKey:key4 inCollection:@"collection2"], @"Oops");
		STAssertNotNil([transaction objectForKey:key5 inCollection:@"collection2"], @"Oops");
	}];
	
	[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		// Test remove all objects from collection
		
		STAssertTrue([transaction numberOfCollections] == 3, @"Incorrect number of collections");
		
		STAssertTrue([transaction numberOfKeysInCollection:nil] == 5, @"Oops");
		STAssertTrue([transaction numberOfKeysInCollection:@"collection1"] == 5, @"Oops");
		STAssertTrue([transaction numberOfKeysInCollection:@"collection2"] == 5, @"Oops");
		
		[transaction removeAllObjectsInCollection:@"collection2"];
	}];
	
	[connection2 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
		
		STAssertTrue([transaction numberOfCollections] == 2, @"Incorrect number of collections");
		
		STAssertTrue([transaction numberOfKeysInCollection:nil] == 5, @"Oops");
		STAssertTrue([transaction numberOfKeysInCollection:@"collection1"] == 5, @"Oops");
		STAssertTrue([transaction numberOfKeysInCollection:@"collection2"] == 0, @"Oops");
		
		STAssertNotNil([transaction objectForKey:key1 inCollection:nil], @"Oops");
		STAssertNotNil([transaction objectForKey:key2 inCollection:nil], @"Oops");
		STAssertNotNil([transaction objectForKey:key3 inCollection:nil], @"Oops");
		STAssertNotNil([transaction objectForKey:key4 inCollection:nil], @"Oops");
		STAssertNotNil([transaction objectForKey:key5 inCollection:nil], @"Oops");
		
		STAssertNotNil([transaction objectForKey:key1 inCollection:@"collection1"], @"Oops");
		STAssertNotNil([transaction objectForKey:key2 inCollection:@"collection1"], @"Oops");
		STAssertNotNil([transaction objectForKey:key3 inCollection:@"collection1"], @"Oops");
		STAssertNotNil([transaction objectForKey:key4 inCollection:@"collection1"], @"Oops");
		STAssertNotNil([transaction objectForKey:key5 inCollection:@"collection1"], @"Oops");
		
		STAssertNil([transaction objectForKey:key1 inCollection:@"collection2"], @"Oops");
		STAssertNil([transaction objectForKey:key2 inCollection:@"collection2"], @"Oops");
		STAssertNil([transaction objectForKey:key3 inCollection:@"collection2"], @"Oops");
		STAssertNil([transaction objectForKey:key4 inCollection:@"collection2"], @"Oops");
		STAssertNil([transaction objectForKey:key5 inCollection:@"collection2"], @"Oops");
	}];
}

- (void)test2
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	STAssertNotNil(database, @"Oops");
	
	/// Test concurrent connections.
	///
	/// Ensure that a read-only transaction can continue while a read-write transaction starts.
	/// Ensure that a read-only transaction can start while a read-write transaction is in progress.
	/// Ensure that a read-only transaction picks up the changes after a read-write transaction.
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
	NSString *key = @"some-key";
	TestObject *object = [TestObject generateTestObject];
	TestObjectMetadata *metadata = [object extractMetadata];
	
	dispatch_queue_t concurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_async(concurrentQueue, ^{
		
		[NSThread sleepForTimeInterval:0.1]; // Zz
		
		[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
			
			[transaction setObject:object forKey:key inCollection:nil withMetadata:metadata];
			
			[NSThread sleepForTimeInterval:0.4]; // Zzzzzzzzzzzzzzzzzzzzzzzzzz
		}];
		
	});
	
	// This transaction should start before the read-write transaction has started
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		STAssertNil([transaction objectForKey:key inCollection:nil], @"Expected nil object");
		STAssertNil([transaction metadataForKey:key inCollection:nil], @"Expected nil metadata");
	}];
	
	[NSThread sleepForTimeInterval:0.2]; // Zzzzzz
	
	// This transaction should start after the read-write transaction has started, but before it has committed
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		STAssertNil([transaction objectForKey:key inCollection:nil], @"Expected nil object");
		STAssertNil([transaction metadataForKey:key inCollection:nil], @"Expected nil metadata");
	}];
	
	[NSThread sleepForTimeInterval:0.4]; // Zzzzzzzzzzzzzzzzzzzzzzzzzz
	
	// This transaction should start after the read-write transaction has completed
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		STAssertNotNil([transaction objectForKey:key inCollection:nil], @"Expected non-nil object");
		STAssertNotNil([transaction metadataForKey:key inCollection:nil], @"Expected non-nil metadata");
	}];
}

- (void)test3
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	STAssertNotNil(database, @"Oops");
	
	/// Test concurrent connections.
	///
	/// Ensure that a read-only transaction properly unblocks a blocked read-write transaction.
	/// Need to turn on logging to check this.
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
	NSString *key = @"some-key";
	TestObject *object = [TestObject generateTestObject];
	TestObjectMetadata *metadata = [object extractMetadata];
	
	dispatch_queue_t concurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_async(concurrentQueue, ^{
		
		[NSThread sleepForTimeInterval:0.2]; // Zz
		
		[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
			
			[transaction setObject:object forKey:key inCollection:nil withMetadata:metadata];
		}];
		
	});
	
	// This transaction should before the read-write transaction
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		[NSThread sleepForTimeInterval:1.0]; // Zzzzzzzzzzz
		
		STAssertNil([transaction objectForKey:key inCollection:nil], @"Expected nil object");
		STAssertNil([transaction metadataForKey:key inCollection:nil], @"Expected nil metadata");
	}];
	
	[NSThread sleepForTimeInterval:0.2]; // Zz
	
	// This transaction should start after the read-write transaction
	[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction){
		
		STAssertNotNil([transaction objectForKey:key inCollection:nil], @"Expected non-nil object");
		STAssertNotNil([transaction metadataForKey:key inCollection:nil], @"Expected non-nil metadata");
	}];
}

- (void)test4
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	STAssertNotNil(database, @"Oops");
	
	/// Ensure large write doesn't block concurrent read operations on other connections.
	
	YapDatabaseConnection *connection1 = [database newConnection];
	YapDatabaseConnection *connection2 = [database newConnection];
	
	__block int32_t doneWritingFlag = 0;
	
	dispatch_queue_t concurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
	dispatch_async(concurrentQueue, ^{
		
		NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
		
		[connection1 readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
			
			int i;
			for (i = 0; i < 100; i++)
			{
				NSString *key = [NSString stringWithFormat:@"some-key-%d", i];
				TestObject *object = [TestObject generateTestObject];
				TestObjectMetadata *metadata = [object extractMetadata];
				
				[transaction setObject:object forKey:key inCollection:nil withMetadata:metadata];
			}
		}];
		
		NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - start;
		NSLog(@"Write operation: %.6f", elapsed);
		
		OSAtomicAdd32(1, &doneWritingFlag);
	});
	
	while (OSAtomicAdd32(0, &doneWritingFlag) == 0)
	{
		NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
		
		[connection2 readWithBlock:^(YapDatabaseReadTransaction *transaction){
			
			(void)[transaction objectForKey:@"some-key-0" inCollection:nil];
		}];
		
		NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - start;
		
		STAssertTrue(elapsed < 0.05, @"Read-Only transaction taking too long...");
	}
}

- (void)testPropertyListSerializerDeserializer
{
	YapDatabaseSerializer propertyListSerializer = [YapDatabase propertyListSerializer];
	YapDatabaseDeserializer propertyListDeserializer = [YapDatabase propertyListDeserializer];
	
	NSDictionary *originalDict = @{ @"date":[NSDate date], @"string":@"string" };
	
	NSData *data = propertyListSerializer(@"collection", @"key", originalDict);
	
	NSDictionary *deserializedDictionary = propertyListDeserializer(@"collection", @"key", data);
	
	STAssertTrue([originalDict isEqualToDictionary:deserializedDictionary], @"PropertyList serialization broken");
}

- (void)testTimestampSerializerDeserializer
{
	YapDatabaseSerializer timestampSerializer = [YapDatabase timestampSerializer];
	YapDatabaseDeserializer timestampDeserializer = [YapDatabase timestampDeserializer];
	
	NSDate *originalDate = [NSDate date];
	
	NSData *data = timestampSerializer(@"collection", @"key", originalDate);
	
	NSDate *deserializedDate = timestampDeserializer(@"collection", @"key", data);
	
	STAssertTrue([originalDate isEqual:deserializedDate], @"Timestamp serialization broken");
}

- (void)testMutationDuringEnumerationProtection
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	STAssertNotNil(database, @"Oops");
	
	// Ensure enumeration protects against mutation
	
	YapDatabaseConnection *connection = [database newConnection];
	
	[connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction setObject:@"object" forKey:@"key1" inCollection:nil];
		[transaction setObject:@"object" forKey:@"key2" inCollection:nil];
		[transaction setObject:@"object" forKey:@"key3" inCollection:nil];
		[transaction setObject:@"object" forKey:@"key4" inCollection:nil];
		[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
	}];
	
	NSArray *keys = @[@"key1", @"key2", @"key3"];
	
	[connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		// enumerateKeysInCollection:
		
		STAssertThrows(
			[transaction enumerateKeysInCollection:nil usingBlock:^(NSString *key, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				// Missing stop; Will cause exception.
			
			}], @"Should throw exception");
		
		STAssertNoThrow(
			[transaction enumerateKeysInCollection:nil usingBlock:^(NSString *key, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				*stop = YES;
			
			}], @"Should NOT throw exception");
		
		
		// enumerateKeysInAllCollectionsUsingBlock:
		
		STAssertThrows(
			[transaction enumerateKeysInAllCollectionsUsingBlock:^(NSString *collection, NSString *key, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				// Missing stop; Will cause exception.
			
			}], @"Should throw exception");
		
		STAssertNoThrow(
			[transaction enumerateKeysInAllCollectionsUsingBlock:^(NSString *collection, NSString *key, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				*stop = YES;
			
			}], @"Should NOT throw exception");
		
		// enumerateMetadataForKeys:inCollection:unorderedUsingBlock:
		
		STAssertThrows(
			[transaction enumerateMetadataForKeys:keys
			                         inCollection:nil
			                  unorderedUsingBlock:^(NSUInteger keyIndex, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				// Missing stop; Will cause exception.
			
			}], @"Should throw exception");
		
		STAssertNoThrow(
			[transaction enumerateMetadataForKeys:keys
			                         inCollection:nil
			                  unorderedUsingBlock:^(NSUInteger keyIndex, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				*stop = YES;
			
			}], @"Should NOT throw exception");
		
		// enumerateObjectsForKeys:inCollection:unorderedUsingBlock:
		
		STAssertThrows(
			[transaction enumerateObjectsForKeys:keys
			                        inCollection:nil
			                 unorderedUsingBlock:^(NSUInteger keyIndex, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				// Missing stop; Will cause exception.
			
			}], @"Should throw exception");
		
		STAssertNoThrow(
			[transaction enumerateObjectsForKeys:keys
			                        inCollection:nil
			                 unorderedUsingBlock:^(NSUInteger keyIndex, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				*stop = YES;
			
			}], @"Should NOT throw exception");
		
		// enumerateRowsForKeys:inCollection:unorderedUsingBlock:
		
		STAssertThrows(
			[transaction enumerateRowsForKeys:keys
			                     inCollection:nil
			              unorderedUsingBlock:^(NSUInteger keyIndex, id object, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				// Missing stop; Will cause exception.
			
			}], @"Should throw exception");
		
		STAssertNoThrow(
			[transaction enumerateRowsForKeys:keys
			                     inCollection:nil
			              unorderedUsingBlock:^(NSUInteger keyIndex, id object, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				*stop = YES;
			
			}], @"Should NOT throw exception");
		
		// enumerateKeysAndMetadataInCollection:usingBlock:
		
		STAssertThrows(
			[transaction enumerateKeysAndMetadataInCollection:nil
			                                       usingBlock:^(NSString *key, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				// Missing stop; Will cause exception.
			
			}], @"Should throw exception");
		
		STAssertNoThrow(
			[transaction enumerateKeysAndMetadataInCollection:nil
			                                       usingBlock:^(NSString *key, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				*stop = YES;
			
			}], @"Should NOT throw exception");
		
		// enumerateKeysAndObjectsInCollection:usingBlock:
		
		STAssertThrows(
			[transaction enumerateKeysAndObjectsInCollection:nil
			                                      usingBlock:^(NSString *key, id object, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				// Missing stop; Will cause exception.
			
			}], @"Should throw exception");
		
		STAssertNoThrow(
			[transaction enumerateKeysAndObjectsInCollection:nil
			                                      usingBlock:^(NSString *key, id object, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				*stop = YES;
			
			}], @"Should NOT throw exception");
		
		// enumerateKeysAndMetadataInAllCollectionsUsingBlock:
		
		STAssertThrows(
			[transaction enumerateKeysAndMetadataInAllCollectionsUsingBlock:
			                                    ^(NSString *collection, NSString *key, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				// Missing stop; Will cause exception.
			
			}], @"Should throw exception");
		
		STAssertNoThrow(
			[transaction enumerateKeysAndMetadataInAllCollectionsUsingBlock:
			                                    ^(NSString *collection, NSString *key, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				*stop = YES;
			
			}], @"Should NOT throw exception");
		
		// enumerateKeysAndObjectsInAllCollectionsUsingBlock:
		
		STAssertThrows(
			[transaction enumerateKeysAndObjectsInAllCollectionsUsingBlock:
			                                    ^(NSString *collection, NSString *key, id object, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				// Missing stop; Will cause exception.
			
			}], @"Should throw exception");
		
		STAssertNoThrow(
			[transaction enumerateKeysAndObjectsInAllCollectionsUsingBlock:
			                                    ^(NSString *collection, NSString *key, id object, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				*stop = YES;
			
			}], @"Should NOT throw exception");
		
		// enumerateRowsInCollection:usingBlock:
		
		STAssertThrows(
			[transaction enumerateRowsInCollection:nil
			                            usingBlock:^(NSString *key, id object, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				// Missing stop; Will cause exception.
			
			}], @"Should throw exception");
		
		STAssertNoThrow(
			[transaction enumerateRowsInCollection:nil
			                            usingBlock:^(NSString *key, id object, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				*stop = YES;
			
			}], @"Should NOT throw exception");
		
		// enumerateRowsInAllCollectionsUsingBlock:
		
		STAssertThrows(
			[transaction enumerateRowsInAllCollectionsUsingBlock:
			                            ^(NSString *collection, NSString *key, id object, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				// Missing stop; Will cause exception.
			
			}], @"Should throw exception");
		
		STAssertNoThrow(
			[transaction enumerateRowsInAllCollectionsUsingBlock:
			                            ^(NSString *collection, NSString *key, id object, id metadata, BOOL *stop) {
				
				[transaction setObject:@"object" forKey:@"key5" inCollection:nil];
				*stop = YES;
			
			}], @"Should NOT throw exception");
	}];
}

@end
