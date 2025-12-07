import 'package:flutter/material.dart';

import '../pages/home_view.dart';

class ProjectCard extends StatelessWidget{
  //Properties
  final String title;

  //Constructor
  const ProjectCard({
    super.key,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {


    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) => HomeViewPage(title: title),),);
      },
      child: Container(
        alignment: Alignment.center,
        height: 75,
        width: 75,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
              color: Colors.green.withValues(alpha: 0.3), // fixed withValues syntax
              width: 1
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder, color: Colors.green,),
            Text(title, style: TextStyle(color: Colors.green),),
          ],
        ),
      ),
    );
  }

}