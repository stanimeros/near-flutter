import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_near/common/firestore_service.dart';
import 'package:flutter_near/widgets/custom_loader.dart';
import 'package:flutter_near/widgets/pick_profile_picture.dart';
import 'package:flutter_near/widgets/popup.dart';
import 'package:flutter_near/common/globals.dart' as globals;
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';

class ProfilePage extends StatefulWidget {
  final authUser = FirebaseAuth.instance.currentUser;

  ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  XFile? newProfilePicture;
  final ImagePicker picker = ImagePicker();

  bool hasChanges = false;
  bool isLoading = false;
  bool uInvalid = false;
  bool kInvalid = false;
  FocusNode uFocusNode = FocusNode();
  FocusNode kFocusNode = FocusNode();
  TextEditingController uController = TextEditingController();
  TextEditingController kController = TextEditingController();
  TextEditingController eController = TextEditingController();
  TextEditingController jController = TextEditingController();

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

  Future<void> saveChanges() async{
    String newUsername = uController.text
      .trim().toLowerCase().replaceAll(' ', '');

    if (!uInvalid && !kInvalid){
      setState(() {
        isLoading = true;
      });

      if (globals.user!.kAnonymity.toString() != kController.text){
        await FirestoreService().setKAnonymity(kController.text);
      }

      if (globals.user!.username != newUsername){
        await FirestoreService().setUsername(newUsername);
      }

      if (newProfilePicture != null){
        await FirestoreService().setProfilePicture(newProfilePicture!.path);
      }

      await FirestoreService().getUser(widget.authUser!.uid);

      setState(() {
        isLoading = false;
        hasChanges = false;
      });
    }
  }

  String? uError(String value) {
    if (value.length < 4){
      return "Username should contain at least 4 characters";
    }else if (value.length > 10){
      return "Username should not contain more than 10 characters";
    }

    return null;
  }

  String? kError(String value) {
    if (value.isEmpty || int.parse(value) == 0){
      return "k Anonymity must be greater than 0";
    }

    return null;
  }

  @override
  void initState() {
    super.initState();
    if (globals.user!.joined != null){
      String dateJoined = 
        '${globals.user!.joined!.day.toString().padLeft(2,'0')}/${globals.user!.joined!.month.toString().padLeft(2,'0')}/${globals.user!.joined!.year}';
      jController = TextEditingController(text: dateJoined);
    }
    uController = TextEditingController(text: globals.user!.username);
    kController = TextEditingController(text: globals.user!.kAnonymity.toString());
    eController = TextEditingController(text: globals.user!.email);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              PickProfilePicture(
                user: globals.user!,
                pickImage: pickImage,
                size: 55,
                color: globals.textColor, 
                backgroundColor: globals.cachedImageColor
              ),
              const SizedBox(width: 12),
              Text(
                globals.user!.username,
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
            focusNode: kFocusNode,
            controller: kController,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2), 
            ],
            onEditingComplete: () {
              setState(() {
                kInvalid = kError(kController.text) != null;
              });
              kFocusNode.unfocus();
            },
            onTapOutside: (event) {
              setState(() {
                kInvalid = kError(kController.text) != null;
              });
              kFocusNode.unfocus();
            },
            onChanged: (value) {
              setState(() {
                hasChanges = true;
              });
            },
            decoration: InputDecoration(
              labelText: 'k Anonymity',
              errorText: kInvalid ? kError(kController.text) : null,
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
          TextField(
            readOnly: true,
            enableInteractiveSelection: false,
            controller: jController,
            decoration: const InputDecoration(
              labelText: 'Joined',
            ),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: () async {
              AlertDialog popUp = PopUp(
                funBtn1: () {
                  Navigator.pop(context);
                  FirestoreService().signOut();
                },
                funBtn2: () {
                  Navigator.pop(context);
                },
              );
          
              showDialog(
                context: context, 
                builder: (BuildContext context) {
                  return popUp;
                }
              );
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Sign out',
                ),
                SizedBox(width: 8),
                Icon(
                  size: 18,
                  LucideIcons.logOut
                )
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () async {
              AlertDialog popUp = PopUp(
                funBtn1: () {
                  Navigator.pop(context);
                  FirestoreService().deleteAccount();
                },
                funBtn2: () {
                  Navigator.pop(context);
                },
              );
          
              showDialog(
                context: context, 
                builder: (BuildContext context) {
                  return popUp;
                }
              );
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Delete your data',
                ),
                SizedBox(width: 8),
                Icon(
                  size: 18,
                  LucideIcons.trash
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}