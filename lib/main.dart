import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_near/pages/friends_page.dart';
import 'package:flutter_near/widgets/bottom_nav_bar.dart';
import 'package:flutter_near/widgets/custom_theme.dart';
import 'package:flutter_near/firebase_options.dart';
import 'package:flutter_near/pages/login_page.dart';
import 'package:flutter_near/pages/profile_page.dart';
import 'package:flutter_near/pages/requests_page.dart';
import 'package:flutter_near/widgets/custom_loader.dart';
import 'package:provider/provider.dart';
import 'package:flutter_near/services/user_provider.dart';
import 'package:flutter_near/services/spatial_db.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SpatialDb().deleteDbFile(SpatialDb.dbFilename); //TODO: Remove this line later
  
  // Initialize both databases
  await SpatialDb().openDbFile(SpatialDb.dbFilename);
  await SpatialDb().createCellsTable(SpatialDb.cells);
  await SpatialDb().createSpatialTable(SpatialDb.pois);
  
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
  late PageController pageController;
  final ValueNotifier<int> _currentIndex = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    pageController = PageController(initialPage: 0);
    pageController.addListener(_handlePageChange);
  }

  @override
  void dispose() {
    pageController.removeListener(_handlePageChange);
    pageController.dispose();
    _currentIndex.dispose();
    super.dispose();
  }

  void _handlePageChange() {
    if (pageController.hasClients && pageController.page != null) {
      _currentIndex.value = pageController.page!.round();
    }
  }

  void changePage(int index) {
    pageController.jumpToPage(index);
    _currentIndex.value = index;
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
                    return const Scaffold(body: CustomLoader());
                  }

                  if (userProvider.nearUser == null) {
                    FirebaseAuth.instance.signOut();
                    return const Scaffold(body: CustomLoader());
                  }

                  return Scaffold(
                    resizeToAvoidBottomInset: false,
                    extendBodyBehindAppBar: false,
                    bottomNavigationBar: ValueListenableBuilder<int>(
                      valueListenable: _currentIndex,
                      builder: (context, currentIndex, _) {
                        return BottomNavBar(
                          changePage: changePage,
                          currentIndex: currentIndex,
                        );
                      },
                    ),
                    body: SafeArea(
                      child: PageView(
                        physics: const NeverScrollableScrollPhysics(),
                        controller: pageController,
                        children: [
                          const FriendsPage(),
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
}
