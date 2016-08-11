//
//  EventViewController.m
//  SeatHeroGuest
//
//  Created by ling toby on 8/4/16.
//  Copyright © 2016 Detroit Labs. All rights reserved.
//

#import "EventViewController.h"
@import FirebaseDatabase;
@import FirebaseAuth;
@import FirebaseStorage;

@interface EventViewController ()
@property (weak, nonatomic) IBOutlet UIImageView *image;
@property (weak, nonatomic) IBOutlet UILabel *nameLabel;
@property (weak, nonatomic) IBOutlet UILabel *lastNameLabel;

@end

@implementation EventViewController

FIRStorageReference *firebaseStorageRef;
FIRStorage *firebaseStorage;


- (void)viewDidLoad {
    [super viewDidLoad];
    NSLog(@"scannedResult is$$$$$$$$$$$$$$$$$$$$$$$$$$ %@ ",_scannedResult);
    [self loginUserToFirebase];
    [self retrieveGuestListFromFirebaseAndAssignToGuestsSortedInGroupList];
}

-(void)updateGuestAttendStatusWithString: (NSString *)string{
    FIRDatabaseReference *guestsRef = [[[FIRDatabase database]reference]child:@"guests"];
    FIRDatabaseReference *currentGuestRef = [guestsRef child:(@"%@",_scannedResult)];
    FIRDatabaseReference *currentGuestRSVPRef = [guestsRef child:(@"%@",_scannedResult)];
    NSDictionary *ifAttend = @{@"ifAttend":string};
    [currentGuestRSVPRef updateChildValues:ifAttend];
}

- (IBAction)attend:(id)sender {
    [self updateGuestAttendStatusWithString:@"Y"];
}

- (IBAction)noAttend:(id)sender {
    [self updateGuestAttendStatusWithString:@"N"];
}

-(void)loginUserToFirebase{
    [[FIRAuth auth] signInWithEmail:@"ling@gmail.com"
                           password:@"123456"
                         completion:^(FIRUser *user, NSError *error) {
                             
                             if (error) {
                                 NSString *message=@"Invalid email or password";
                                 NSString *alertTitle=@"Invalid!";
                                 NSString *OKText=@"OK";
                                 
                                 UIAlertController *alertView = [UIAlertController alertControllerWithTitle:alertTitle message:message preferredStyle:UIAlertControllerStyleAlert];
                                 UIAlertAction *alertAction = [UIAlertAction actionWithTitle:OKText style:UIAlertActionStyleCancel handler:nil];
                                 [alertView addAction:alertAction];
                                 [self presentViewController:alertView animated:YES completion:nil];
                             }
                         }];
}

#pragma mark Firebase Methods

//initializes Firebase Storage and creates reference to it.
-(void)firebaseSetUp {
    firebaseStorage = [FIRStorage storage];
    firebaseStorageRef = [_firebaseStorage referenceForURL:@"gs://wire-e0cde.appspot.com"];
}

//Gets the current user's UserProfile from Firebase.
-(void)getCurrentUserProfileFromFirebase {
    FIRDatabaseReference *UserProfileRef = [[[FIRDatabase database]reference]child:@"userprofile"];
    FIRDatabaseQuery *currentUserProfileQuery = [[UserProfileRef queryOrderedByChild:@"userId"] queryEqualToValue:[FIRAuth auth].currentUser.uid];
    [currentUserProfileQuery observeEventType:FIRDataEventTypeChildAdded withBlock:^(FIRDataSnapshot *snapshot) {
        _currentUserProfileKey = snapshot.key;
        _currentUser = [[UserProfile alloc]initUserProfileWithEmail:snapshot.value[@"email"] username:snapshot.value[@"username"] uid:snapshot.value[@"userId"]];
        _currentUser.profileImageDownloadURL = snapshot.value[@"profilePhotoDownloadURL"];
        _currentUser.profileImage = [UIImage imageWithData:[NSData dataWithContentsOfURL:[NSURL URLWithString:snapshot.value[@"profilePhotoDownloadURL"]]]];
        dispatch_async(dispatch_get_main_queue(), ^{
            [_currentUserProfilePhoto setImage:_currentUser.profileImage];
            [_usernameLabel setText:[NSString stringWithFormat:@"Hello, %@!", _currentUser.username]];
        });
    }];
}

/*
 Listens for changes to the current user's UserProfile.
 This uses FIRDataEventTypeChildChange, which is similar to FIRDataEventTypeChildAdded
 except that it occurrs when a child node's value is changed in some way and not
 when a new child is added.
 */
-(void)listenForChangesInUserProfile {
    FIRDatabaseReference *UserProfileRef = [[[FIRDatabase database]reference]child:@"userprofile"];
    FIRDatabaseQuery *currentUserProfileChangedQuery = [[UserProfileRef queryOrderedByChild:@"userId"] queryEqualToValue:[FIRAuth auth].currentUser.uid];
    
    [currentUserProfileChangedQuery observeEventType:FIRDataEventTypeChildChanged withBlock:^(FIRDataSnapshot *snapshot) {
        _currentUser = [[UserProfile alloc]initUserProfileWithEmail:snapshot.value[@"email"] username:snapshot.value[@"username"] uid:snapshot.value[@"userId"]];
        _currentUser.profileImageDownloadURL = snapshot.value[@"profilePhotoDownloadURL"];
        _currentUser.profileImage = [UIImage imageWithData:[NSData dataWithContentsOfURL:[NSURL URLWithString:snapshot.value[@"profilePhotoDownloadURL"]]]];
        NSLog(@"_current user URL: %@", _currentUser.profileImageDownloadURL);
        dispatch_async(dispatch_get_main_queue(), ^{
            [_currentUserProfilePhoto setImage:_currentUser.profileImage];
            [_usernameLabel setText:[NSString stringWithFormat:@"Hello, %@!", _currentUser.username]];
        });
    }];
}

/*
 This accepts the NSData that is returned from the image picker and then saves it on Firebase Storage.
 Once it is stored in Firebase storage it gives us back a downloadURL.
 */
-(void)uploadPhotoToFirebase:(NSData *)imageData {
    //Create a uniqueID for the image and add it to the end of the images reference.
    NSString *uniqueID = [[NSUUID UUID]UUIDString];
    NSString *newImageReference = [NSString stringWithFormat:@"profilePhotos/%@.jpg", uniqueID];
    //imagesRef creates a reference for the images folder and then adds a child to that folder, which will be every time a photo is taken.
    FIRStorageReference *imagesRef = [_firebaseStorageRef child:newImageReference];
    //This uploads the photo's NSData onto Firebase Storage.
    FIRStorageUploadTask *uploadTask = [imagesRef putData:imageData metadata:nil completion:^(FIRStorageMetadata *metadata, NSError *error) {
        if (error) {
            NSLog(@"ERROR: %@", error.description);
        } else {
            _currentUser.profileImageDownloadURL = metadata.downloadURL.absoluteString;
            [self updateCurrentUserProfileImageDownloadURLOnFirebaseDatabase:_currentUser];
        }
    }];
    [uploadTask resume];
}

/*
 This accepts a UserProfile object to update (which will be our current user profile).
 When the UserProfile object is passed it will already have an updated URL from when the new photo
 is taken and the metaDataURL is sent back. It then updates the child node on Firebase.
 */
-(void)updateCurrentUserProfileImageDownloadURLOnFirebaseDatabase:(UserProfile *)userProfile {
    
    FIRDatabaseReference *firebaseRef = [[FIRDatabase database] reference];
    
    /*
     Need every value filled or it will just remove what we didn't put in the dictionary.
     For an example if the profileImageDownloadURL was the only thing we put in this dictionary
     and used this dictionary to update the child node then the email, userId and the username
     would be removed and only the profilePhotoDownloadURL would be in that child node.
     */
    NSDictionary *userProfileToUpdate = @{@"profilePhotoDownloadURL": userProfile.profileImageDownloadURL,
                                          @"email": userProfile.email,
                                          @"userId": userProfile.uid,
                                          @"username": userProfile.username};
    
    NSDictionary *childUpdates = @{[@"/userprofile/" stringByAppendingString:_currentUserProfileKey]: userProfileToUpdate};
    
    [firebaseRef updateChildValues:childUpdates];
    
}





     //retrieve all the guest information from firebaseRef->guests then convert from dictionary to Guest type, append it to GuestsSortedInGroupList by its group type
-(void)retrieveGuestListFromFirebaseAndAssignToGuestsSortedInGroupList{
         FIRDatabaseReference *guestsRef = [[[FIRDatabase database]reference]child:@"guests"];
         FIRDatabaseReference *currentGuestRef = [guestsRef child:(@"%@",_scannedResult)];
         NSLog(@"%@",currentGuestRef.description);
         [currentGuestRef observeEventType:FIRDataEventTypeValue withBlock:
          ^(FIRDataSnapshot *snapshot) {
              NSLog(@"______________%@ %@", [snapshot.value objectForKey:@"firstName"],[snapshot.value objectForKey:@"lastName"]);
              _nameLabel.text = (@"%@",[snapshot.value objectForKey:@"firstName"]);
              _lastNameLabel.text = (@"%@",[snapshot.value objectForKey:@"lastName"]);}];
}
     
- (IBAction)changeUserImage:(id)sender {
    [self presentCamera];
}

    

@end
