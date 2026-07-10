import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ChatPage extends StatefulWidget {
  final String myPhone;
  final String otherPhone;
  final String contactName;

  const ChatPage({
    super.key,
    required this.myPhone,
    required this.otherPhone,
    required this.contactName,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController messageController = TextEditingController();
  final ScrollController scrollController = ScrollController();

  late String chatId;
  bool isTyping = false;
  String otherStatus = "offline";
  String lastSeen = "";

  String normalize(String p) {
    final d = p.replaceAll(RegExp(r'\D'), '');
    return d.length > 10 ? d.substring(d.length - 10) : d;
  }

  @override
  void initState() {
    super.initState();

    final a = normalize(widget.myPhone);
    final b = normalize(widget.otherPhone);
    final list = [a, b]..sort();
    chatId = "${list[0]}_${list[1]}";

    setOnline(true);
    listenToTyping();
    listenToStatus();
  }

  @override
  void dispose() {
    setOnline(false);
    messageController.dispose();
    super.dispose();
  }

  // 🔹 Update online/offline + last seen
  Future<void> setOnline(bool online) async {
    await FirebaseFirestore.instance.collection("users").doc(normalize(widget.myPhone)).set({
      "online": online,
      "lastSeen": FieldValue.serverTimestamp(),
      "typing": false,
    }, SetOptions(merge: true));
  }

  // 🔹 Listen to typing status of other user
  void listenToTyping() {
    FirebaseFirestore.instance
        .collection("users")
        .doc(normalize(widget.otherPhone))
        .snapshots()
        .listen((doc) {
      if (!doc.exists) return;
      setState(() {
        isTyping = doc["typing"] ?? false;
      });
    });
  }

  // 🔹 Listen to online/offline + last seen
  void listenToStatus() {
    FirebaseFirestore.instance
        .collection("users")
        .doc(normalize(widget.otherPhone))
        .snapshots()
        .listen((doc) {
      if (!doc.exists) return;

      bool online = doc["online"] ?? false;
      Timestamp? ts = doc["lastSeen"];

      setState(() {
        otherStatus = online ? "online" : "offline";
        lastSeen = ts != null ? DateFormat('hh:mm a').format(ts.toDate()) : "";
      });
    });
  }

  // 🔹 Send message
  Future<void> sendMessage() async {
    final text = messageController.text.trim();
    if (text.isEmpty) return;

    final my = normalize(widget.myPhone);
    final other = normalize(widget.otherPhone);

    messageController.clear();

    FirebaseFirestore.instance.collection("users").doc(my).update({"typing": false});

    await FirebaseFirestore.instance.collection("chats").doc(chatId).collection("messages").add({
      "text": text,
      "sender": my,
      "timestamp": FieldValue.serverTimestamp(),
      "seenBy": [my],
    });

    await FirebaseFirestore.instance.collection("chats").doc(chatId).set({
      "lastMessage": text,
      "lastTime": FieldValue.serverTimestamp(),
      "unreadFor": [other],
    }, SetOptions(merge: true));

    Future.delayed(const Duration(milliseconds: 200), () {
      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final my = normalize(widget.myPhone);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.contactName),
            Text(
              isTyping
                  ? "typing..."
                  : otherStatus == "online"
                      ? "online"
                      : "last seen $lastSeen",
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
      ),

      resizeToAvoidBottomInset: true,

      body: Column(
        children: [
          // 🔹 MESSAGES LIST
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection("chats")
                  .doc(chatId)
                  .collection("messages")
                  .orderBy("timestamp")
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snap.data!.docs;

                Future.delayed(const Duration(milliseconds: 100), () {
                  if (scrollController.hasClients) {
                    scrollController.jumpTo(
                        scrollController.position.maxScrollExtent);
                  }
                });

                return ListView.builder(
                  controller: scrollController,
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final data = docs[i].data() as Map<String, dynamic>;
                    final sender = data["sender"];
                    final text = data["text"] ?? "";
                    final isMe = sender == my;

                    final seenBy = (data["seenBy"] ?? []) as List;
                    if (!isMe && !seenBy.contains(my)) {
                      docs[i].reference.update({
                        "seenBy": FieldValue.arrayUnion([my])
                      });
                    }

                    final ts = data["timestamp"];
                    final time = ts == null
                        ? ""
                        : DateFormat("hh:mm a").format(ts.toDate());

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.blue : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              text,
                              style: TextStyle(
                                color: isMe ? Colors.white : Colors.black,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  time,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isMe ? Colors.white70 : Colors.black54,
                                  ),
                                ),
                                if (isMe)
                                  Icon(
                                    seenBy.length > 1 ? Icons.done_all : Icons.done,
                                    size: 16,
                                    color: seenBy.length > 1 ? Colors.lightBlue : Colors.white70,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // 🔹 INPUT BAR
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: messageController,
                      onChanged: (txt) {
                        FirebaseFirestore.instance
                            .collection("users")
                            .doc(normalize(widget.myPhone))
                            .update({"typing": txt.isNotEmpty});
                      },
                      decoration: const InputDecoration(
                        hintText: "Message...",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(24)),
                        ),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  CircleAvatar(
                    backgroundColor: Colors.blue,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: sendMessage,
                    ),
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
