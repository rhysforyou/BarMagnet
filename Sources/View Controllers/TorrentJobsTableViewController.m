//
//  FirstViewController.m
//  BarMagnet
//
//  Created by Charlotte Tortorella on 4/06/13.
//  Copyright (c) 2013 Charlotte Tortorella. All rights reserved.
//

#import "TorrentJobsTableViewController.h"
#import "FileHandler.h"
#import "M13OrderedDictionary.h"
#import "SVModalWebViewController.h"
#import "SVWebViewController.h"
#import "TSMessage.h"
#import "TorrentDelegate.h"
#import "TorrentJobCheckerCell.h"
#import "TransferTotal.h"

#define IPHONE_HEIGHT 22
#define IPAD_HEIGHT 28

enum ORDER { COMPLETED = 1,
             INCOMPLETE,
             DOWNLOAD_SPEED,
             UPLOAD_SPEED,
             ACTIVE,
             DOWNLOADING,
             SEEDING,
             PAUSED,
             NAME,
             SIZE,
             RATIO,
             DATE_ADDED,
             DATE_FINISHED };

@interface TorrentJobsTableViewController () <UISearchControllerDelegate, UISearchResultsUpdating, UIScrollViewDelegate, NSFileManagerDelegate>
@property(nonatomic, strong) NSMutableArray *filteredArray;
@property(nonatomic, strong) UILabel *header;
@property(nonatomic, strong) NSArray *sortedKeys;
@property(nonatomic, strong) NSMutableOrderedDictionary *sortByDictionary;
@property(nonatomic, strong) TransferTotal * transferTotalView;
@property(nonatomic, strong) UISearchController *searchController;
@end

@implementation TorrentJobsTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [TSMessage setDefaultViewController:self];
    [self initialiseUploadDownloadLabels];
    [self initialiseHeader];
    self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Back" style:UIBarButtonItemStylePlain target:nil action:nil];
    self.title = [FileHandler.sharedInstance settingsValueForKey:@"server_name"];
    [self.tableView accessibilityScroll:UIAccessibilityScrollDirectionDown];

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.delegate = self;
    self.searchController.searchResultsUpdater = self;
    self.searchController.dimsBackgroundDuringPresentation = NO;
    self.searchController.hidesNavigationBarDuringPresentation = YES;
    self.definesPresentationContext = YES;
    if (@available(iOS 11.0, *)) {
        self.tableView.tableHeaderView = nil;
        self.navigationItem.searchController = self.searchController;
    } else {
        self.tableView.tableHeaderView = self.searchController.searchBar;
    }
    
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(receiveUpdateTableNotification) name:@"update_torrent_jobs_table" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(receiveUpdateHeaderNotification) name:@"update_torrent_jobs_header" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(changedClient) name:@"ChangedClient" object:nil];
}

- (void)initialiseUploadDownloadLabels {
    self.transferTotalView = [[NSBundle mainBundle] loadNibNamed:@"TransferTotal" owner:self options:nil][0];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.transferTotalView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.shouldRefresh = YES;
    self.sortByDictionary = [NSMutableOrderedDictionary.alloc initWithObjects:@[
        @(COMPLETED), @(DATE_ADDED), @(DATE_FINISHED), @(DOWNLOAD_SPEED), @(UPLOAD_SPEED), @(ACTIVE), @(NAME), @(SIZE), @(RATIO), @(DOWNLOADING), @(SEEDING),
        @(PAUSED)
    ]
                                                               pairedWithKeys:@[
                                                                   @"Progress", @"Date Added", @"Date Finished", @"Download Speed", @"Upload Speed", @"Active",
                                                                   @"Name", @"Size", @"Ratio", @"Downloading", @"Seeding", @"Paused"
                                                               ]];
    self.tableView.rowHeight =
        [[self.tableView dequeueReusableCellWithIdentifier:@"Compact"] frame].size.height;
    [self receiveUpdateTableNotification];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)changedClient {
    self.title = [FileHandler.sharedInstance settingsValueForKey:@"server_name"];
}

- (void)initialiseHeader {
    self.header = [UILabel.alloc initWithFrame:CGRectMake(0, 0, self.tableView.frame.size.width, [self sizeForDevice])];
    self.header.backgroundColor = [UIColor systemGreenColor];
    self.header.textColor = [UIColor whiteColor];
    self.header.text = @"Attempting Connection";
    self.header.font = [UIFont fontWithName:@"Arial" size:self.sizeForDevice - 6];
    self.header.textAlignment = NSTextAlignmentCenter;
    self.header.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
}

- (void)receiveUpdateTableNotification {
    if (!cancelNextRefresh) {
        dispatch_async(dispatch_get_main_queue(), ^{
          if (self.shouldRefresh && !self.tableView.isEditing && !self.tableView.isDragging && !self.tableView.isDecelerating) {
              [self.tableView reloadData];
          }
        });
    } else {
        cancelNextRefresh = NO;
    }
    [self createDownloadUploadTotals];
}

- (void)receiveUpdateHeaderNotification {
    if ([TorrentDelegate.sharedInstance.currentlySelectedClient isHostOnline]) {
        self.header.backgroundColor = [UIColor systemBlueColor];
        self.header.text = @"Host Online";
    } else {
        self.header.backgroundColor = [UIColor systemRedColor];
        self.header.text = @"Host Offline";
    }
}

- (void)willPresentSearchController:(UISearchController *)searchController {
    self.shouldRefresh = NO;
}

- (void)willDismissSearchController:(UISearchController *)searchController {
    self.shouldRefresh = YES;
    [self receiveUpdateTableNotification];
}

- (IBAction)addTorrentPopup:(id)sender {
    UIAlertController *addTorrentAlert = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleAlert];
    [addTorrentAlert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [addTorrentAlert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        
    }];
    [addTorrentAlert addAction:[UIAlertAction actionWithTitle:@"Open URL" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *text = addTorrentAlert.textFields.firstObject.text;
        if (text.length == 0) {
            return;
        }
        NSString *magnet = @"magnet:";
        if (text.length > magnet.length && [[text substringWithRange:NSMakeRange(0, magnet.length)] isEqual:magnet]) {
            [[TorrentDelegate sharedInstance] handleMagnet:text];
            [self.navigationController popViewControllerAnimated:YES];
        } else if ([text rangeOfString:@".torrent"].location != NSNotFound) {
            [[TorrentDelegate sharedInstance] handleTorrentFile:text];
            [self.navigationController popViewControllerAnimated:YES];
        } else {
            if ([text rangeOfString:@"https://"].location != NSNotFound || [text rangeOfString:@"http://"].location != NSNotFound) {
                SVModalWebViewController *webViewController = [[SVModalWebViewController alloc] initWithAddress:text];
                [self.navigationController presentViewController:webViewController animated:YES completion:nil];
            } else {
                SVModalWebViewController *webViewController = [[SVModalWebViewController alloc]
                                                               initWithAddress:[@"http://" stringByAppendingString:[text stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]]]];
                [self.navigationController presentViewController:webViewController animated:YES completion:nil];
            }
        }
    }]];
    [addTorrentAlert addAction:[UIAlertAction actionWithTitle:@"Search via Queries" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self performSegueWithIdentifier:@"query" sender:nil];
    }]];
    [addTorrentAlert addAction:[UIAlertAction actionWithTitle:@"Scan QR Core" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self performSegueWithIdentifier:@"scan" sender:nil];
    }]];
    [self presentViewController:addTorrentAlert animated:YES completion:nil];
}

- (IBAction)showListOfControlOptions:(id)sender {
    UIAlertController *controller = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [controller addAction:[UIAlertAction actionWithTitle:@"Resume All" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [TorrentDelegate.sharedInstance.currentlySelectedClient resumeAllTorrents];
    }]];
    [controller addAction:[UIAlertAction actionWithTitle:@"Pause All" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [TorrentDelegate.sharedInstance.currentlySelectedClient pauseAllTorrents];
    }]];
    [controller addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    controller.popoverPresentationController.sourceView = sender;
    [self presentViewController:controller animated:YES completion:nil];
}

- (void)showSortBySheet {
    UIAlertController *sortController = [UIAlertController alertControllerWithTitle:@"Sort By" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    
    for (NSString *string in self.sortByDictionary.allKeys) {
        [sortController addAction:[UIAlertAction actionWithTitle:string style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [FileHandler.sharedInstance setSettingsValue:string forKey:@"sort_by"];
            [self.tableView reloadData];
        }]];
    }

    [sortController addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    sortController.popoverPresentationController.sourceView = self.navigationController.toolbar;
    [self presentViewController:sortController animated:YES completion:nil];
}

- (void)showOrderBySheet {
    UIAlertController *orderByController = [UIAlertController alertControllerWithTitle:@"Order As" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    
    [orderByController addAction:[UIAlertAction actionWithTitle:@"Ascending" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [FileHandler.sharedInstance setSettingsValue:@-1 forKey:@"order_by"];
        [self.tableView reloadData];
    }]];
    [orderByController addAction:[UIAlertAction actionWithTitle:@"Descending" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [FileHandler.sharedInstance setSettingsValue:@1 forKey:@"order_by"];
        [self.tableView reloadData];
    }]];
    
    [orderByController addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    orderByController.popoverPresentationController.sourceView = self.navigationController.toolbar;
    [self presentViewController:orderByController animated:YES completion:nil];
}

- (IBAction)sortAndOrder:(id)sender {
    NSInteger orderBy = [[FileHandler.sharedInstance settingsValueForKey:@"order_by"] integerValue];
    NSString *title = [NSString stringWithFormat:@"%@, %@", [FileHandler.sharedInstance settingsValueForKey:@"sort_by"],
                       orderBy != NSOrderedAscending ? @"Descending" : @"Ascending"];
    UIAlertController *sortAndOrderController = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sortAndOrderController addAction:[UIAlertAction actionWithTitle:@"Order As" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self showOrderBySheet];
    }]];
    [sortAndOrderController addAction:[UIAlertAction actionWithTitle:@"Sort By" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self showSortBySheet];
    }]];
    
    [sortAndOrderController addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    sortAndOrderController.popoverPresentationController.sourceView = self.navigationController.toolbar;
    [self presentViewController:sortAndOrderController animated:YES completion:nil];
}

- (void)deleteTorrentWithHash:(NSUInteger)hash removeData:(BOOL)removeData {
    self.shouldRefresh = NO;
    NSString *hashString = nil;
    NSUInteger index = 0;
    for (NSDictionary *dict in self.sortedKeys) {
        if ([dict[@"hash"] hash] == hash) {
            hashString = dict[@"hash"];
            index = [self.sortedKeys indexOfObject:dict];
            break;
        }
    }
    
    if (hashString) {
        [NSNotificationCenter.defaultCenter postNotificationName:@"cancel_refresh" object:nil];
        [TorrentDelegate.sharedInstance.currentlySelectedClient addTemporaryDeletedJob:4 forKey:hashString];
        [TorrentDelegate.sharedInstance.currentlySelectedClient removeTorrent:hashString removeData:removeData];
        [self.tableView deleteRowsAtIndexPaths:@[ [NSIndexPath indexPathForRow:index inSection:0] ] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        self.shouldRefresh = YES;
    });
}

- (IBAction)openUI:(id)sender {
    if ([[TorrentDelegate.sharedInstance.currentlySelectedClient getUserFriendlyAppendedURL] length]) {
        SVModalWebViewController *webViewController =
            [SVModalWebViewController.alloc initWithAddress:TorrentDelegate.sharedInstance.currentlySelectedClient.getUserFriendlyAppendedURL];
        [self presentViewController:webViewController animated:YES completion:nil];
    }
}

- (NSComparisonResult)orderBy:(NSComparisonResult)orderBy comparing:(NSDictionary *)a with:(NSDictionary *)b usingKey:(NSString *)key {
    if (a[key] && b[key]) {
        NSComparisonResult res = orderBy != NSOrderedAscending ? [a[key] compare:b[key]] : [b[key] compare:a[key]];
        return res != NSOrderedSame ? res : [a[@"name"] compare:b[@"name"]];
    }
    return [a[@"name"] compare:b[@"name"]];
}

- (void)sortArray:(NSMutableArray *)array {
    NSInteger orderBy = [[FileHandler.sharedInstance settingsValueForKey:@"order_by"] integerValue];
    NSInteger sortBy = [self.sortByDictionary[[FileHandler.sharedInstance settingsValueForKey:@"sort_by"]] integerValue];
    switch (sortBy) {
    case COMPLETED:
    case INCOMPLETE: {
        [array
            sortUsingComparator:(NSComparator) ^ (NSDictionary * a, NSDictionary * b) { return [self orderBy:orderBy comparing:b with:a usingKey:@"progress"]; }];
        break;
    }
    case DOWNLOAD_SPEED: {
        [array sortUsingComparator:(NSComparator) ^
                                   (NSDictionary * a, NSDictionary * b) { return [self orderBy:orderBy comparing:b with:a usingKey:@"rawDownloadSpeed"]; }];
        break;
    }
    case UPLOAD_SPEED: {
        [array sortUsingComparator:(NSComparator) ^
                                   (NSDictionary * a, NSDictionary * b) { return [self orderBy:orderBy comparing:b with:a usingKey:@"rawUploadSpeed"]; }];
        break;
    }
    case ACTIVE: {
        [array sortUsingComparator:(NSComparator) ^ (NSDictionary * a, NSDictionary * b) {
            if ([a[@"rawUploadSpeed"] integerValue] | [a[@"rawDownloadSpeed"] integerValue]) {
                if (!([b[@"rawUploadSpeed"] integerValue] | [b[@"rawDownloadSpeed"] integerValue])) {
                    return orderBy != NSOrderedAscending ? NSOrderedAscending : NSOrderedDescending;
                }
            } else if ([b[@"rawUploadSpeed"] integerValue] | [b[@"rawDownloadSpeed"] integerValue]) {
                return orderBy != NSOrderedAscending ? NSOrderedDescending : NSOrderedAscending;
            }
            return [a[@"name"] compare:b[@"name"]];
        }];
        break;
    }
    case DOWNLOADING:
    case SEEDING:
    case PAUSED: {
        [array sortUsingComparator:(NSComparator) ^ (NSDictionary * a, NSDictionary * b) {
            if ([self.sortByDictionary[a[@"status"]] integerValue] == sortBy) {
                if (!([self.sortByDictionary[b[@"status"]] integerValue] == sortBy)) {
                    return orderBy != NSOrderedAscending ? NSOrderedAscending : NSOrderedDescending;
                }
            } else if ([self.sortByDictionary[b[@"status"]] integerValue] == sortBy) {
                return orderBy != NSOrderedAscending ? NSOrderedDescending : NSOrderedAscending;
            }
            return [a[@"name"] compare:b[@"name"]];
        }];
        break;
    }
    case SIZE: {
        [array sortUsingComparator:(NSComparator) ^ (NSDictionary * a, NSDictionary * b) { return [self orderBy:orderBy comparing:b with:a usingKey:@"size"]; }];
        break;
    }
    case RATIO: {
        [array sortUsingComparator:(NSComparator) ^ (NSDictionary * a, NSDictionary * b) { return [self orderBy:orderBy comparing:b with:a usingKey:@"ratio"]; }];
        break;
    }
    case DATE_ADDED: {
        [array
            sortUsingComparator:(NSComparator) ^ (NSDictionary * a, NSDictionary * b) { return [self orderBy:orderBy comparing:b with:a usingKey:@"dateAdded"]; }];
        break;
    }
    case DATE_FINISHED: {
        [array
            sortUsingComparator:(NSComparator) ^ (NSDictionary * a, NSDictionary * b) { return [self orderBy:orderBy comparing:b with:a usingKey:@"dateDone"]; }];
        break;
    }
    default:
    case NAME: {
        [array sortUsingComparator:(NSComparator) ^ (NSDictionary * a, NSDictionary * b) {
            return orderBy != NSOrderedAscending ? [b[@"name"] compare:a[@"name"]] : [a[@"name"] compare:b[@"name"]];
        }];
        break;
    }
    }
}

- (void)createDownloadUploadTotals {
    [TransferTotal new];
    NSUInteger uploadSpeed = 0, downloadSpeed = 0;
    for (NSDictionary *dict in TorrentDelegate.sharedInstance.currentlySelectedClient.getJobsDict.allValues) {
        if (dict[@"rawUploadSpeed"] && dict[@"rawDownloadSpeed"]) {
            uploadSpeed += [dict[@"rawUploadSpeed"] integerValue];
            downloadSpeed += [dict[@"rawDownloadSpeed"] integerValue];
        }
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        self.transferTotalView.uploadSpeedLabel.text = @(uploadSpeed).transferRateString;
        self.transferTotalView.downloadSpeedLabel.text = @(downloadSpeed).transferRateString;
    });
}

- (void)addProgressViewToCell:(TorrentJobCheckerCell *)cell withJob:(NSDictionary *)currentJob {
    NSInteger tag = -(1 << 8);
    if (![[cell viewWithTag:tag].class isEqual:UIView.class]) {
        UIView *view = [UIView.alloc initWithFrame:cell.frame];
        view.tag = tag;
        [cell insertSubview:view atIndex:0];
    }

    UIView *progressView = [cell viewWithTag:tag];
    CGRect frame = progressView.frame;
    double completeValue = [[[TorrentDelegate.sharedInstance.currentlySelectedClient class] completeNumber] doubleValue];
    frame.size.width = cell.frame.size.width * (completeValue ? [currentJob[@"progress"] doubleValue] / completeValue : 0);
    progressView.frame = frame;

    [progressView setNeedsDisplay];
}

- (void)showDeletePopupForHash:(NSUInteger)hash atIndexPath:(NSIndexPath *)indexPath {
    BOOL supportsDelete = TorrentDelegate.sharedInstance.currentlySelectedClient.supportsEraseChoice;
    NSString *title = supportsDelete ? @"Also delete data?" : @"Are you sure?";
    
    UIAlertController *deleteController = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [deleteController addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (supportsDelete) {
        [deleteController addAction:[UIAlertAction actionWithTitle:@"Delete data" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            [self deleteTorrentWithHash:hash removeData:YES];
        }]];
    }
    
    [deleteController addAction:[UIAlertAction actionWithTitle:@"Delete torrent" style:supportsDelete ? UIAlertActionStyleDefault : UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [self deleteTorrentWithHash:hash removeData:NO];
    }]];
    deleteController.popoverPresentationController.sourceView = [self.tableView cellForRowAtIndexPath:indexPath];
    deleteController.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:indexPath];
    [self presentViewController:deleteController animated:YES completion:nil];
}

- (CGFloat)sizeForDevice {
    return [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone ? IPHONE_HEIGHT : IPAD_HEIGHT;
}

#pragma mark - Navigation

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.destinationViewController isKindOfClass:TorrentDetailViewController.class]) {
        if ([sender isKindOfClass:TorrentJobCheckerCell.class]) {
            [segue.destinationViewController setHashString:[sender hashString]];
        } else if ([sender isKindOfClass:NSString.class]) {
            [segue.destinationViewController setHashString:sender];
        }
    }
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    NSMutableArray *dictValues = [TorrentDelegate.sharedInstance.currentlySelectedClient.getJobsDict.allValues mutableCopy];
    [self sortArray:dictValues];
    self.sortedKeys = dictValues;
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.searchController.active) {
        return self.filteredArray.count;
    }
    return [[[TorrentDelegate.sharedInstance.currentlySelectedClient getJobsDict] allKeys] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    TorrentJobCheckerCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"Compact"];
    if ([cell.subviews.firstObject isKindOfClass:UIScrollView.class]) {
        [cell.subviews.firstObject setDelegate:self];
    }
    NSDictionary *currentJob = nil;

    if (self.searchController.active) {
        currentJob = self.filteredArray[indexPath.row];
    } else {
        currentJob = self.sortedKeys[indexPath.row];
    }

    cell.name.text = currentJob[@"name"];
    cell.hashString = currentJob[@"hash"];
    cell.currentStatus.text = currentJob[@"status"];

    double completeValue = [TorrentDelegate.sharedInstance.currentlySelectedClient.class completeNumber].doubleValue;
    cell.percentBar.progress = completeValue ? [currentJob[@"progress"] doubleValue] / completeValue : 0;

    if ([currentJob[@"ETA"] isKindOfClass:[NSString class]] && [currentJob[@"ETA"] length] &&
        [currentJob[@"progress"] doubleValue] != [[TorrentDelegate.sharedInstance.currentlySelectedClient.class completeNumber] doubleValue]) {
        cell.ETA.text = [NSString stringWithFormat:@"ETA: %@", currentJob[@"ETA"]];
    } else if (currentJob[@"ratio"]) {
        cell.ETA.text = [NSString stringWithFormat:@"Ratio: %.3f", [currentJob[@"ratio"] doubleValue]];
    } else {
        cell.ETA.text = @"";
    }
    cell.downloadSpeed.text = [NSString stringWithFormat:@"%@ ↓", currentJob[@"downloadSpeed"]];

    if ([currentJob[@"status"] isEqualToString:@"Seeding"]) {
        cell.percentBar.progressTintColor = [UIColor systemGreenColor];
    } else if ([currentJob[@"status"] isEqualToString:@"Downloading"]) {
        cell.percentBar.progressTintColor = [UIColor systemBlueColor];
    } else {
        cell.percentBar.progressTintColor = [UIColor systemGrayColor];
    }

    cell.uploadSpeed.text = [NSString stringWithFormat:@"↑ %@", currentJob[@"uploadSpeed"]];
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        UIFont *font = [UIFont fontWithName:@"Arial" size:10];
        cell.downloadSpeed.font = font;
        cell.uploadSpeed.font = font;
        cell.currentStatus.font = font;
        cell.ETA.font = font;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    self.tableView = tableView;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.shouldRefresh;
}

#pragma mark - Table View Delegate

- (void)tableView:(UITableView *)tableView didEndEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    cancelNextRefresh = NO;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    cancelNextRefresh = YES;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return [self sizeForDevice];
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return self.shouldRefresh ? self.header : nil;
}


- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleNone;
}

#pragma mark - Search

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    NSDictionary *currentJob = nil;
    if (self.searchController.active) {
        currentJob = self.filteredArray[indexPath.row];
    } else {
        currentJob = self.sortedKeys[indexPath.row];
    }

    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggestedActions) {
        UIAction *delete = [UIAction actionWithTitle:@"Delete" image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(__kindof UIAction * _Nonnull action) {
            [self showDeletePopupForHash:[currentJob[@"hash"] hash] atIndexPath:indexPath];
        }];

        UIAction *resumeOrPauseAction;
        if ([currentJob[@"status"] isEqualToString:@"Paused"]) {
            resumeOrPauseAction = [UIAction actionWithTitle:@"Resume" image:[UIImage systemImageNamed:@"play"] identifier:nil handler:^(__kindof UIAction * _Nonnull action) {
                [TorrentDelegate.sharedInstance.currentlySelectedClient resumeTorrent:currentJob[@"hash"]];
            }];
        } else {
            resumeOrPauseAction = [UIAction actionWithTitle:@"Pause" image:[UIImage systemImageNamed:@"pause"] identifier:nil handler:^(__kindof UIAction * _Nonnull action) {
                [TorrentDelegate.sharedInstance.currentlySelectedClient pauseTorrent:currentJob[@"hash"]];
            }];
        }

        return [UIMenu menuWithTitle:@"" children:@[delete, resumeOrPauseAction]];
    }];
}

- (BOOL)searchBarShouldBeginEditing:(UISearchBar *)searchBar {
    return [[[TorrentDelegate.sharedInstance.currentlySelectedClient getJobsDict] allKeys] count] ? YES : NO;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self filterContentForSearchText:searchController.searchBar.text];
    [self.tableView reloadData];
}

- (void)filterContentForSearchText:(NSString *)searchText {
    NSDictionary *jobs = [TorrentDelegate.sharedInstance.currentlySelectedClient getJobsDict];
    if (searchText.length == 0) {
        self.filteredArray = [NSMutableArray arrayWithArray:jobs.allValues];
    } else {
        self.filteredArray = NSMutableArray.new;
        for (NSDictionary *job in jobs.allValues) {
            if ([[job[@"name"] lowercaseString] rangeOfString:[searchText lowercaseString]].location != NSNotFound) {
                [self.filteredArray addObject:job];
            }
        }
    }
    [self sortArray:self.filteredArray];
}

#pragma mark - Scroll View Delegate

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    cancelNextRefresh = YES;
}

@end
