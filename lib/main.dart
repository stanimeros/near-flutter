import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_near/widgets/bottom_nav_bar.dart';
import 'package:flutter_near/widgets/custom_theme.dart';
import 'package:flutter_near/services/db_helper.dart';
import 'package:flutter_near/firebase_options.dart';
import 'package:flutter_near/pages/feed_page.dart';
import 'package:flutter_near/pages/friends_page.dart';
import 'package:flutter_near/pages/login_page.dart';
import 'package:flutter_near/pages/profile_page.dart';
import 'package:flutter_near/pages/requests_page.dart';
import 'package:flutter_near/pages/map_page.dart';
import 'package:flutter_near/widgets/custom_loader.dart';
import 'package:provider/provider.dart';
import 'package:flutter_near/services/user_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DbHelper().openDbFile();
  await DbHelper().createSpatialTable(DbHelper.pois);

  // DbHelper().deleteDb();
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
          if (snapshot.hasData) {
            return ChangeNotifierProvider(
              create: (_) => UserProvider()..loadNearUser(),
              child: Consumer<UserProvider>(
                builder: (context, userProvider, _) {
                  if (userProvider.isLoading) {
                    return const Scaffold(
                      body: CustomLoader(),
                    );
                  }

                  if (userProvider.nearUser == null) {
                    FirebaseAuth.instance.signOut();
                    return const Scaffold(
                      body: CustomLoader(),
                    );
                  }

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
                          const MapPage(),
                          const RequestsPage(),
                          const ProfilePage(),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          } else {
            return const LoginPage();
          }
        },
      ),
    );
  }

  void changePage(index) {
    setState(() {
      pageController.jumpToPage(index);
    });
  }
}
