import 'package:flutter/material.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}


class _HomeState extends State<Home>{

  @override
  Widget build(BuildContext context) {
    
    return Scaffold(
      backgroundColor: Colors.white70,
      body: SizedBox(
        height: 500,
        width: 500,
        child: Text("Hello there"),
      ),
    );



  }
}