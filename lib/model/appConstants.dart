import 'dart:io';
import 'package:chopper/chopper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:iit_app/data/post_api_service.dart';
import 'package:iit_app/model/LocalDatabase/databaseQuery.dart';
import 'package:iit_app/model/LocalDatabase/databaseWrite.dart';
import 'package:iit_app/model/built_post.dart';
import 'package:iit_app/model/LocalDatabase/database_helpers.dart';
import 'package:built_collection/built_collection.dart';
import 'package:iit_app/services/connectivityCheck.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class AppConstants {
  //for guest user
  static bool isGuest = false;

// TODO: define minimum padding for safe area here so that it can be constant over whole app

  // static EdgeInsets safeAreaMinPadding = EdgeInsets.fromLTRB(2, 2, 2, 2);

  static ConnectionStatusSingleton connectionStatus;
  static bool isLoggedIn = false;
  // static bool isOnline = false;
  // static Stream connectivityStream;

  // ------------------------------------------ connectivity variables

  static bool logInButtonEnabled = true;
  static bool firstTimeFetching = true;

  static bool chooseColorPaletEnabled = false;

  static String deviceDirectoryPathImages;

  static String djangoToken;

  static User currentUser;
  static PostApiService service;

  static BuiltList<BuiltWorkshopSummaryPost> workshopFromDatabase;
  static BuiltList<BuiltAllCouncilsPost> councilsSummaryfromDatabase;
  static BuiltList<EntityListPost> entitiesSummaryFromDatabase;

  static Future setDeviceDirectoryForImages() async {
    String path = (await getApplicationDocumentsDirectory()).path + '/Images';

    Directory(path).exists().then((exist) {
      if (exist == false) {
        Directory(path).createSync();
      }
      AppConstants.deviceDirectoryPathImages = path;
    });
  }

  static Future populateWorkshopsAndCouncilAndEntityButtons() async {
    DatabaseHelper helper = DatabaseHelper.instance;
    var database = await helper.database;

    councilsSummaryfromDatabase =
        await DatabaseQuery.getAllCouncilsSummary(db: database);
    workshopFromDatabase =
        await DatabaseQuery.getAllWorkshopsSummary(db: database);
    entitiesSummaryFromDatabase =
        await DatabaseQuery.getAllEntitiesSummary(db: database);
    // print(' workshops is empty: ${(workshops.isEmpty == true).toString()}');

    if (workshopFromDatabase == null) {
      // insert all workshop information for the first time
      await DatabaseWrite.deleteAllWorkshopsSummary(db: database);
      await DatabaseWrite.deleteAllCouncilsSummary(db: database);
      await DatabaseWrite.deleteAllEntitySummary(db: database);

      print(
          'fetching workshops and all councils and entites summary from json');

// API calls to fetch the data
      final workshopSnapshots = await service.getActiveWorkshops();
      final workshopPosts = workshopSnapshots.body;

      final councilSummarySnapshots = await service.getAllCouncils();
      final councilSummaryPosts = councilSummarySnapshots.body;

      final entitySummarySnapshots = await service.getAllEntity();
      final entitySummaryPosts = entitySummarySnapshots.body;

// storing the data fetched from json objects into local database
      // ? remember, we use council summary in database while fetching other data (most of time)
      await DatabaseWrite.insertCouncilSummaryIntoDatabase(
          councils: councilSummaryPosts, db: database);

      councilSummaryPosts.forEach((council) async {
        await writeImageFileIntoDisk(
            isCouncil: true,
            isSmall: true,
            id: council.id,
            url: council.small_image_url);
      });

      await DatabaseWrite.insertEntitiesSummaryIntoDatabase(
          db: database, entities: entitySummaryPosts);

      entitySummaryPosts.forEach((entity) async {
        await writeImageFileIntoDisk(
            isEntity: true,
            isSmall: true,
            id: entity.id,
            url: entity.small_image_url);
      });

      for (var post in workshopPosts) {
        await DatabaseWrite.insertWorkshopSummaryIntoDatabase(
            post: post, db: database);
        writeImageFileIntoDisk(
            isClub: true,
            isSmall: true,
            id: post.club == null ? post.entity.id : post.club.id,
            url: post.club == null
                ? post.entity.small_image_url
                : post.club.small_image_url);
      }

// fetching the data from local database and storing it into variables
// whose scope is throughout the app

      councilsSummaryfromDatabase = councilSummaryPosts;
      // await helper.getAllCouncilsSummary(db: database);
      workshopFromDatabase = workshopPosts;
      // await helper.getAllWorkshopsSummary(db: database);
      entitiesSummaryFromDatabase = entitySummaryPosts;
    }

    // helper.closeDatabase(db: database);
    print('workshops and all councils and entities summary fetched ');
  }

  static writeCouncilAndEntityLogoIntoDisk() async {
    councilsSummaryfromDatabase?.forEach((council) async {
      await writeImageFileIntoDisk(
          isCouncil: true,
          isSmall: true,
          id: council.id,
          url: council.small_image_url);
    });
    entitiesSummaryFromDatabase?.forEach((entity) async {
      await writeImageFileIntoDisk(
          isEntity: true,
          isSmall: true,
          id: entity.id,
          url: entity.small_image_url);
    });
  }

  /// if [isSmall] is false, then image will be considered as large
  ///
  /// [id] will be served for any option , [isCouncil] or [isClub] , whichever is true
  ///
  /// if [isCouncil] and [isClub] both are true/false , function produces zero work.
  static writeImageFileIntoDisk(
      {bool isCouncil = false,
      bool isClub = false,
      bool isEntity = false,
      @required bool isSmall,
      @required int id,
      @required String url}) async {
    int truthCount = 0;
    if (isCouncil) truthCount++;
    if (isClub) truthCount++;
    if (isEntity) truthCount++;

    if (truthCount != 1 ||
        isSmall == null ||
        id == null ||
        url == null ||
        url == "") {
      return;
    }

    String size = isSmall ? 'small' : 'large';
    String host = isCouncil ? 'council' : 'club';

    if (isEntity) {
      host = 'entity';
    }

    File file =
        File('${AppConstants.deviceDirectoryPathImages}/$host($size)_$id');

    if (file.existsSync() == false) {
      http.get(url).catchError((error) {
        print('Error in downloading image : $error');
        print('for $host , id = $id');
      }).then((response) {
        if (response != null && response.statusCode == 200) {
          final imageData = response.bodyBytes.toList();
          final File writingFile = File(
              '${AppConstants.deviceDirectoryPathImages}/$host($size)_$id');
          writingFile.writeAsBytesSync(imageData);
          print('image saved into disk = $host , id = $id');
        }
      });
    }
  }

  /// if file doesn't exist, null is returned
  ///
  /// if [isSmall] is false, then image will be considered as large
  ///
  /// [id] will be served for any option , [isCouncil] or [isClub] , whichever is true
  ///
  /// if [isCouncil] and [isClub] both are true/false, null will be returned

  static File getImageFile({
    bool isCouncil = false,
    bool isClub = false,
    bool isEntity = false,
    @required bool isSmall,
    @required int id,
  }) {
    int truthCount = 0;
    if (isCouncil) truthCount++;
    if (isClub) truthCount++;
    if (isEntity) truthCount++;

    if (truthCount != 1 || isSmall == null || id == null) {
      return null;
    }

    String size = isSmall ? 'small' : 'large';
    File file;
    String host = isCouncil ? 'council' : 'club';
    if (isEntity) {
      host = 'entity';
    }
    file = File('${AppConstants.deviceDirectoryPathImages}/$host($size)_$id');

    if (file.existsSync()) {
      return file;
    } else
      return null;
  }

// TODO: we fetch council and entity summaries only once in while initializing empty database, make it refreshable.

  static Future updateAndPopulateWorkshops() async {
    DatabaseHelper helper = DatabaseHelper.instance;
    var database = await helper.database;

    print('fetching workshops infos from json for updation');

    Response<BuiltList<BuiltWorkshopSummaryPost>> workshopSnapshots =
        await service.getActiveWorkshops();

    if (workshopSnapshots.body != null) {
      await DatabaseWrite.deleteAllWorkshopsSummary(db: database);
      final workshopPosts = workshopSnapshots.body;

      for (var post in workshopPosts) {
        await DatabaseWrite.insertWorkshopSummaryIntoDatabase(
            post: post, db: database);
      }
      workshopFromDatabase = workshopPosts;
    }
    print('workshops fetched and updated ');
  }

  static Future getCouncilDetailsFromDatabase(
      {@required int councilId, bool refresh = false}) async {
    DatabaseHelper helper = DatabaseHelper.instance;
    var database = await helper.database;

    BuiltCouncilPost councilPost = await DatabaseQuery.getCouncilDetail(
        db: database, councilId: councilId);

    if (councilPost == null || refresh == true) {
      Response<BuiltCouncilPost> councilSnapshots = await AppConstants.service
          .getCouncil(AppConstants.djangoToken, councilId);

      if (councilSnapshots.body != null) {
        councilPost = councilSnapshots.body;

        await DatabaseWrite.insertCouncilDetailsIntoDatabase(
            councilPost: councilPost, db: database);
      }
    }

    return councilPost;
  }

  static Future<BuiltClubPost> getClubDetailsFromDatabase(
      {@required int clubId, bool refresh = false}) async {
    DatabaseHelper helper = DatabaseHelper.instance;
    var database = await helper.database;

    BuiltClubPost clubPost =
        await DatabaseQuery.getClubDetails(db: database, clubId: clubId);

    if (clubPost == null || refresh == true) {
      Response<BuiltClubPost> clubSnapshots = await AppConstants.service
          .getClub(clubId, AppConstants.djangoToken)
          .catchError((onError) {
        print("Error in fetching clubs: ${onError.toString()}");
      });

      if (clubSnapshots.body != null) {
        clubPost = clubSnapshots.body;

        await DatabaseWrite.insertClubDetailsIntoDatabase(
            clubPost: clubPost, db: database);
      }
    }

    return clubPost;
  }

  static Future updateClubSubscriptionInDatabase(
      {@required int clubId,
      @required bool isSubscribed,
      @required int currentSubscribedUsers}) async {
    DatabaseHelper helper = DatabaseHelper.instance;
    var database = await helper.database;

    final subscribedUsers = currentSubscribedUsers + (isSubscribed ? 1 : -1);

    await DatabaseWrite.updateClubSubcription(
        db: database,
        clubId: clubId,
        isSubscribed: isSubscribed,
        subscribedUsers: subscribedUsers);
  }

  static Future getEntityDetailsFromDatabase(
      {@required int entityId, bool refresh = false}) async {
    DatabaseHelper helper = DatabaseHelper.instance;
    var database = await helper.database;

    BuiltEntityPost entityPost;
    await DatabaseQuery.getEntityDetails(db: database, entityId: entityId);

    if (entityPost == null || refresh == true) {
      Response<BuiltEntityPost> entitySnapshots = await AppConstants.service
          .getEntity(entityId, AppConstants.djangoToken)
          .catchError((onError) {
        print("Error in fetching entity: ${onError.toString()}");
      });
      if (entitySnapshots.body != null) {
        entityPost = entitySnapshots.body;

        await DatabaseWrite.insertEntityDetailsIntoDatabase(
            entityPost: entityPost, db: database);
      }
    }

    return entityPost;
  }

  static Future updateEntitySubscriptionInDatabase(
      {@required int entityId,
      @required bool isSubscribed,
      @required int currentSubscribedUsers}) async {
    DatabaseHelper helper = DatabaseHelper.instance;
    var database = await helper.database;

    final subscribedUsers = currentSubscribedUsers + (isSubscribed ? 1 : -1);

    await DatabaseWrite.updateEntitySubcription(
        db: database,
        entityId: entityId,
        isSubscribed: isSubscribed,
        subscribedUsers: subscribedUsers);
  }

  /// All locally stored data will be deleted ( only database not images).
  static Future deleteLocalDatabaseOnly() async {
    DatabaseHelper helper = DatabaseHelper.instance;
    var database = await helper.database;
    await DatabaseWrite.deleteWholeDatabase(db: database);
  }

  /// All locally stored data will be deleted (database and images).
  static Future deleteAllLocalDataWithImages() async {
    DatabaseHelper helper = DatabaseHelper.instance;
    var database = await helper.database;
    await DatabaseWrite.deleteWholeDatabase(db: database);
    print('-----------------------------');
    Directory(AppConstants.deviceDirectoryPathImages)
        .listSync(recursive: true)
        .forEach((f) {
      print('deleted : ' +
          (f.path.split('Images/').length > 1
              ? f.path.split('Images/')[1]
              : 'nothing was here'));
      f.deleteSync();
    });

    AppConstants.firstTimeFetching = true;
    AppConstants.workshopFromDatabase = null;
    AppConstants.councilsSummaryfromDatabase = null;
    AppConstants.entitiesSummaryFromDatabase = null;
  }

  static String addEventToCalendarLink(
      {@required BuiltWorkshopDetailPost workshop}) {
    final String initialUrlForCalendar =
        "https://www.google.com/calendar/render?action=TEMPLATE";

    final String title =
        "${workshop.title} - (${workshop.club?.name ?? workshop.entity?.name ?? ''})";

    String date = workshop.date.substring(0, 4) +
        workshop.date.substring(5, 7) +
        workshop.date.substring(8, 10);
    String startTime = convertTimeToUtc(workshop.time);
    String endTime = convertTimeToUtc(workshop.time, true);
    final String urlLink = initialUrlForCalendar +
        '&text=' +
        Uri.encodeFull(title) +
        '&dates=' +
        date +
        'T' +
        startTime +
        'Z' +
        '/' +
        date +
        'T' +
        endTime +
        'Z';
    return urlLink;
  }

  static String convertTimeToUtc(String time, [bool addHour = false]) {
    if (time == null) {
      return addHour ? '190000' : '180000';
    }
    int hour = int.parse(time.substring(0, 2));
    if (addHour) {
      hour += 1;
    }
    int minute = int.parse(time.substring(3, 5));
    if (minute >= 30) {
      hour -= 5;
      minute -= 30;
    } else {
      hour -= 6;
      minute += 30;
    }
    return (hour.toString() + minute.toString() + '00');
  }
}
