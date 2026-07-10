import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'chat_page.dart';

class HomePage extends StatefulWidget {
  final String myPhone;

  const HomePage({super.key, required this.myPhone});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {

  List<Contact> contacts = [];
  bool loading = true;
  String search = "";

  String normalize(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
  }

  @override
  void initState() {
    super.initState();
    loadContacts();
    saveFCMToken();
  }

  Future<void> saveFCMToken() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;

    final my = normalize(widget.myPhone);

    await FirebaseFirestore.instance.collection("users").doc(my).set({
      "fcmToken": token,
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> loadContacts() async {

    final permission = await FlutterContacts.requestPermission(readonly: true);

    if (!permission) {
      setState(() => loading = false);
      return;
    }

    final result = await FlutterContacts.getContacts(withProperties: true);

    setState(() {
      contacts = result;
      loading = false;
    });
  }

  String chatId(String other) {
    final a = normalize(widget.myPhone);
    final b = normalize(other);

    final list = [a, b]..sort();

    return "${list[0]}_${list[1]}";
  }

  @override
  Widget build(BuildContext context) {

    final my = normalize(widget.myPhone);

    return Scaffold(

      appBar: AppBar(
        title: const Text("VKConnect"),
      ),

      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [

                Padding(
                  padding: const EdgeInsets.all(8),
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: "Search Contact",
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      setState(() {
                        search = v.toLowerCase();
                      });
                    },
                  ),
                ),

                Expanded(
                  child: ListView.builder(
                    itemCount: contacts.length,
                    itemBuilder: (context, i) {

                      final contact = contacts[i];

                      if (contact.displayName.isEmpty ||
                          contact.phones.isEmpty) {
                        return const SizedBox();
                      }

                      if (search.isNotEmpty &&
                          !contact.displayName
                              .toLowerCase()
                              .contains(search)) {
                        return const SizedBox();
                      }

                      final phone =
                          normalize(contact.phones.first.number);

                      final id = chatId(phone);

                      return ListTile(

                        leading: CircleAvatar(
                          backgroundColor: Colors.blue,
                          child: Text(
                            contact.displayName[0].toUpperCase(),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),

                        title: Text(contact.displayName),

                        subtitle: StreamBuilder<DocumentSnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection("chats")
                              .doc(id)
                              .snapshots(),
                          builder: (context, snap) {

                            if (!snap.hasData) {
                              return const Text("");
                            }

                            final data =
                                snap.data!.data() as Map<String, dynamic>?;

                            final last =
                                data?["lastMessage"] ?? phone;

                            return Text(
                              last,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            );
                          },
                        ),

                        onTap: () {

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChatPage(
                                myPhone: widget.myPhone,
                                otherPhone: phone,
                                contactName: contact.displayName,
                              ),
                            ),
                          );

                        },
                      );
                    },
                  ),
                )
              ],
            ),
    );
  }
}