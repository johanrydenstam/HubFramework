/*
 *  Copyright (c) 2016 Spotify AB.
 *
 *  Licensed to the Apache Software Foundation (ASF) under one
 *  or more contributor license agreements.  See the NOTICE file
 *  distributed with this work for additional information
 *  regarding copyright ownership.  The ASF licenses this file
 *  to you under the Apache License, Version 2.0 (the
 *  "License"); you may not use this file except in compliance
 *  with the License.  You may obtain a copy of the License at
 *
 *  http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing,
 *  software distributed under the License is distributed on an
 *  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 *  KIND, either express or implied.  See the License for the
 *  specific language governing permissions and limitations
 *  under the License.
 */

#import <XCTest/XCTest.h>

#import "HUBCollectionViewLayoutMock.h"
#import "HUBCollectionViewMock.h"
#import "HUBComponentLayoutManagerMock.h"
#import "HUBViewModelDiff.h"
#import "HUBViewModelRenderer.h"
#import "HUBViewModelUtilities.h"

/**
 *  We don't want these tests to be concerned with the inner workings of the batch update process, as this invokes
 *  a lot of collection view logic that over-complicates the test (e.g. checking that the items rendered before
 *  the batch update tallies with the number of items after the batch update).
 *
 *  To get around this, we override the insert, delete and reload methods to do nothing.
 */
@interface HUBCollectionViewMockWithoutBatchUpdates : HUBCollectionViewMock

@end

@implementation HUBCollectionViewMockWithoutBatchUpdates

- (void)insertItemsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths
{
}

- (void)deleteItemsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths
{
}

- (void)reloadItemsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths
{
}

@end

@interface HUBViewModelRenderer (HUBUnitTest)

@property (nonatomic, strong, nullable) id<HUBViewModel> lastRenderedViewModel;

@end

@interface HUBViewModelRendererTests : XCTestCase

@property (nonatomic, strong) HUBCollectionViewMockWithoutBatchUpdates *collectionView;
@property (nonatomic, strong) HUBCollectionViewLayoutMock *collectionViewLayout;
@property (nonatomic, strong) HUBViewModelRenderer *viewModelRenderer;

@end

@implementation HUBViewModelRendererTests

- (void)setUp
{
    [super setUp];

    self.collectionView = [HUBCollectionViewMockWithoutBatchUpdates new];
    self.collectionViewLayout = [[HUBCollectionViewLayoutMock alloc] init];
    self.collectionView.collectionViewLayout = self.collectionViewLayout;
    self.viewModelRenderer = [HUBViewModelRenderer new];
}

- (void)tearDown
{
    self.collectionView = nil;
    self.collectionViewLayout = nil;
    self.viewModelRenderer = nil;

    [super tearDown];
}

- (void)testTwoSubsequentRenders
{
    NSArray<id<HUBComponentModel>> *firstComponents = @[
        [HUBViewModelUtilities createComponentModelWithIdentifier:@"component-1" customData:nil],
    ];
    id<HUBViewModel> firstViewModel = [HUBViewModelUtilities createViewModelWithIdentifier:@"Test" components:firstComponents];

    NSArray<id<HUBComponentModel>> *secondComponents = @[
        [HUBViewModelUtilities createComponentModelWithIdentifier:@"component-2" customData:nil],
    ];
    id<HUBViewModel> secondViewModel = [HUBViewModelUtilities createViewModelWithIdentifier:@"Test2" components:secondComponents];

    __weak XCTestExpectation * const expectation = [self expectationWithDescription:@"Waiting for render"];

    [self.viewModelRenderer renderViewModel:firstViewModel inCollectionView:self.collectionView usingBatchUpdates:YES animated:YES addHeaderMargin:YES completion:^{
        // Immediately trigger another render.
        [self.viewModelRenderer renderViewModel:secondViewModel inCollectionView:self.collectionView usingBatchUpdates:YES animated:YES addHeaderMargin:YES completion:^{
            [expectation fulfill];
        }];
    }];

    [self waitForExpectationsWithTimeout:2 handler:nil];

    XCTAssertEqual(self.collectionViewLayout.capturedViewModels.count, 2u);
    XCTAssertEqualObjects(self.collectionViewLayout.capturedViewModels[0], firstViewModel);
    XCTAssertEqualObjects(self.collectionViewLayout.capturedViewModels[1], secondViewModel);

    XCTAssertEqual(self.collectionViewLayout.capturedViewModelDiffs.count, 2u);
    // The first invocation shouldn't generate a diff.
    XCTAssertEqualObjects(self.collectionViewLayout.capturedViewModelDiffs[0], [NSNull null]);
    // The second invocation should generate a diff.
    HUBViewModelDiff *diff = self.collectionViewLayout.capturedViewModelDiffs[1];
    XCTAssertNotEqualObjects(diff, [NSNull null]);

    XCTAssertEqual(diff.insertedBodyComponentIndexPaths.count, 1u);
    XCTAssertEqual(diff.deletedBodyComponentIndexPaths.count, 1u);
    XCTAssertEqual(diff.reloadedBodyComponentIndexPaths.count, 0u);
}

- (void)testThatRenderingTwoViewModelsShouldSetSecondToLastRenderedViewModel
{
    __weak XCTestExpectation * const expectation = [self expectationWithDescription:@"Waiting for completion"];

    NSArray<id<HUBComponentModel>> *firstComponents = @[
                                                        [HUBViewModelUtilities createComponentModelWithIdentifier:@"component-1" customData:nil],
                                                        ];
    id<HUBViewModel> firstViewModel = [HUBViewModelUtilities createViewModelWithIdentifier:@"Test" components:firstComponents];

    NSArray<id<HUBComponentModel>> *secondComponents = @[
                                                         [HUBViewModelUtilities createComponentModelWithIdentifier:@"component-2" customData:nil],
                                                         [HUBViewModelUtilities createComponentModelWithIdentifier:@"component-3" customData:nil]
                                                         ];
    id<HUBViewModel> secondViewModel = [HUBViewModelUtilities createViewModelWithIdentifier:@"Test2" components:secondComponents];

    __weak __typeof(self) weakSelf = self;
    [self.viewModelRenderer renderViewModel:firstViewModel
                           inCollectionView:self.collectionView
                          usingBatchUpdates:YES
                                   animated:YES
                            addHeaderMargin:YES completion:^{

                                __typeof(self) strongSelf = weakSelf;
                                [strongSelf.viewModelRenderer renderViewModel:secondViewModel
                                                             inCollectionView:strongSelf.collectionView
                                                            usingBatchUpdates:YES
                                                                     animated:YES
                                                              addHeaderMargin:YES
                                                                   completion:^{
                                                                       [expectation fulfill];
                                                                   }];
                            }];

    [self waitForExpectationsWithTimeout:2.0 handler:^(NSError * _Nullable error) {
        XCTAssertNil(error);
        XCTAssertEqual(self.viewModelRenderer.lastRenderedViewModel, secondViewModel);
    }];
}

@end
