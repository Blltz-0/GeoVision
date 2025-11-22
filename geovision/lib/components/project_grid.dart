import 'package:flutter/material.dart';
import 'package:geovision/components/project_card.dart';



class ProjectGrid extends StatelessWidget{
  //Properties
  final int columns;
  final int itemCount;
  final List<Map<String, dynamic>> dataList;

  //Constructor
  const ProjectGrid({
    super.key,
    required this.columns,
    required this.itemCount,
    required this.dataList,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      physics: NeverScrollableScrollPhysics(),
      itemBuilder: (BuildContext context, int index) {
        // 3. Grab the specific data for THIS position
        final item = dataList[index];

        // 4. Pass that data into your Card
        return ProjectCard(title: item["title"],
        );
      },
      itemCount: dataList.length,
    );
  }
}