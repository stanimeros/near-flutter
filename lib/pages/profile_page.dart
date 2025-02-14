import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_near/services/firestore.dart';
import 'package:flutter_near/widgets/custom_loader.dart';
import 'package:flutter_near/widgets/pick_profile_picture.dart';
import 'package:flutter_near/widgets/popup.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:flutter_near/services/user_provider.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  XFile? newProfilePicture;
  final ImagePicker picker = ImagePicker();

  bool hasChanges = false;
  bool isLoading = false;
  bool uInvalid = false;
  FocusNode uFocusNode = FocusNode();
  TextEditingController uController = TextEditingController();
  TextEditingController eController = TextEditingController();
  double kValue = 2; // Default k-anonymity value

  @override
  void initState() {
    super.initState();
    final userProvider = context.read<UserProvider>();
    final nearUser = userProvider.nearUser;
    
    uController = TextEditingController(text: nearUser?.username);
    eController = TextEditingController(text: nearUser?.email);
    kValue = (nearUser?.kAnonymity ?? 2).toDouble();
  }

  Future<void> saveChanges() async {
    final userProvider = context.read<UserProvider>();
    final nearUser = userProvider.nearUser;
    if (nearUser == null) return;

    String newUsername = uController.text
      .trim().toLowerCase().replaceAll(' ', '');

    if (!uInvalid) {
      setState(() {
        isLoading = true;
      });

      try {
        // Update user data in Firestore
        await FirestoreService().setUser(nearUser.uid, newUsername, kValue.round().toString());

        // Update profile picture if changed
        if (newProfilePicture != null) {
          await FirestoreService().setProfilePicture(nearUser.uid, newProfilePicture!.path);
        }

        // Get updated user data
        final updatedUser = await FirestoreService().getUser(nearUser.uid);
        if (updatedUser != null) {
          // Update the provider without notifying listeners
          userProvider.updateUserSilently(updatedUser);
        }

        if (mounted) {
          setState(() {
            isLoading = false;
            hasChanges = false;
          });
        }
      } catch (e) {
        debugPrint('Error saving changes: $e');
        if (mounted) {
          setState(() {
            isLoading = false;
          });
        }
      }
    }
  }

  String? uError(String value) {
    if (value.length < 4) {
      return "Username should contain at least 4 characters";
    } else if (value.length > 10) {
      return "Username should not contain more than 10 characters";
    }
    return null;
  }

  Future<XFile?> pickImage() async {
    final XFile? selectedImage = await picker.pickImage(
      source: ImageSource.gallery,
      maxHeight: 512,
      maxWidth: 512,
    );
    
    setState(() {
      newProfilePicture = selectedImage;
      hasChanges = true;
    });

    return newProfilePicture;
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    
    if (userProvider.isLoading) {
      return const CustomLoader();
    }

    final nearUser = userProvider.nearUser;
    if (nearUser == null) {
      return const Text('No user data');
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              PickProfilePicture(
                user: nearUser,
                pickImage: pickImage,
                size: 55,
                color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black,
                backgroundColor: Theme.of(context).colorScheme.surface
              ),
              const SizedBox(width: 12),
              Text(
                nearUser.username,
                style: const TextStyle(
                  fontSize: 20
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 50,
                child: Visibility(
                  visible: hasChanges,
                  child: isLoading ? const CustomLoader()
                  : IconButton(
                    onPressed: () {
                      saveChanges();
                    },
                    icon: const Icon(
                      size: 18,
                      LucideIcons.save
                    ),
                  ),
                ),
              )
            ]
          ),
          const SizedBox(height: 20),
          TextField(
            focusNode: uFocusNode,
            controller: uController,
            onEditingComplete: () {
              setState(() {
                uInvalid = uError(uController.text) != null;
              });
              uFocusNode.unfocus();
            },
            onTapOutside: (event) {
              setState(() {
                uInvalid = uError(uController.text) != null;
              });
              uFocusNode.unfocus();
            },
            onChanged: (value) {
              setState(() {
                hasChanges = true;
              });
            },
            decoration: InputDecoration(
              labelText: 'Username',
              errorText: uInvalid ? uError(uController.text) : null,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            readOnly: true,
            enableInteractiveSelection: false,
            controller: eController,
            decoration: const InputDecoration(
              labelText: 'Email',
            ),
          ),
          const SizedBox(height: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'k-Anonymity: ${kValue.round()}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Slider(
                value: kValue,
                min: 2,
                max: 20,
                divisions: 18,
                label: kValue.round().toString(),
                onChanged: (value) {
                  setState(() {
                    kValue = value;
                    hasChanges = true;
                  });
                },
              ),
            ],
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: () async {
              AlertDialog popUp = PopUp(
                funBtn1: () {
                  Navigator.pop(context);
                  FirebaseAuth.instance.signOut();
                },
                funBtn2: () {
                  Navigator.pop(context);
                },
              );
              showDialog(
                context: context,
                builder: (BuildContext context) => popUp,
              );
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Sign out'),
                SizedBox(width: 8),
                Icon(LucideIcons.logOut, size: 18)
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}