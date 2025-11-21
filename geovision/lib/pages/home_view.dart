import 'package:flutter/material.dart';
import 'package:geovision/pages/project_container.dart';

class HomeViewPage extends StatelessWidget {
  const HomeViewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Third Page'),

      ),
      body: Center(
        child: Text('You made it to the new page!'),
      ),
      bottomNavigationBar: BottomAppBar(
        color: Colors.white,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: () {
                Navigator.pop(context);
              },
              child: Container(
                  height: 40,
                  width:100,
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.white,
                      border: Border.all(
                        color: Colors.black54.withValues(alpha: 0.3),
                        width: 2,
                      )
                  ),
                  alignment: Alignment.center,
                  child: Text("Back")
              ),
            ),
            GestureDetector(
              onTap: () {
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const ProjectContainerPage()),);
              },
              child: Container(
                  height: 40,
                  width:100,
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.blueAccent,
                      border: Border.all(
                        color: Colors.black54.withValues(alpha: 0.1),
                        width: 2,
                      )
                  ),
                  alignment: Alignment.center,
                  child: Text("Confirm",style: TextStyle(
                    color: Colors.white,
                  ),)
              ),
            ),

          ],
        ),
      ),
    );
  }
}