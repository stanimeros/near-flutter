import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_near/bars/bottom_nav_bar.dart';
import 'package:flutter_near/common/custom_theme.dart';
import 'package:flutter_near/common/firestore_service.dart';
import 'package:flutter_near/common/db_helper.dart';
import 'package:flutter_near/common/near_user.dart';
import 'package:flutter_near/firebase_options.dart';
import 'package:flutter_near/pages/chats_page.dart';
import 'package:flutter_near/pages/feed_page.dart';
import 'package:flutter_near/pages/friends_page.dart';
import 'package:flutter_near/pages/login_page.dart';
import 'package:flutter_near/pages/profile_page.dart';
import 'package:flutter_near/widgets/custom_loader.dart';
import 'package:flutter_near/widgets/messenger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dbHelper.initializeDb();
  await dbHelper.createSpatialTable(dbHelper.pois);
  await dbHelper.createSpatialTable(dbHelper.keys);
  // dbHelper.deleteDb();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
);
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  PageController pageController = PageController(initialPage: 0);

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: CustomTheme.themeData,
      home: StreamBuilder(
        stream: FirebaseAuth.instance.authStateChanges(), 
        builder: (context, snapshot) {
          if (snapshot.hasData){
            return FutureBuilder(
              future: FirestoreService().initializeUser(),
              builder: (context, snapshot) {
                if (snapshot.hasData){
                  NearUser? user = snapshot.data;
                  if (user != null){
                    return Scaffold(
                      resizeToAvoidBottomInset: false,
                      extendBodyBehindAppBar: false,
                      bottomNavigationBar: BottomNavBar(changePage: changePage),
                      body: SafeArea(
                        child: PageView(
                          physics: const NeverScrollableScrollPhysics(),
                          controller: pageController,
                          children: [
                            const FeedPage(),
                            const FriendsPage(),
                            ChatsPage(),
                            ProfilePage()
                          ],
                        ),
                      )
                    );
                  }
                  return const Scaffold(
                    body: Messenger(message: 'Error: User not found')
                  );
                }
                return const Scaffold(
                  body: CustomLoader()
                );
              }
            );
          }else{
            return const LoginPage();
          }
        }
      )
    );
  }

  void changePage(index) {
    setState(() {
      pageController.jumpToPage(index);
    });
  }
}
