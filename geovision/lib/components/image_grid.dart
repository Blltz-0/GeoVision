import 'package:flutter/material.dart';

import '../pages/image_view.dart';
import 'image_card.dart';


class ImageGrid extends StatelessWidget{
  //Properties
  final int columns;
  final int itemCount;
  final List<Map<String, dynamic>> dataList;
  final String projectName;
  final VoidCallback onBack;

  //Constructor
  const ImageGrid({
    super.key,
    required this.columns,
    required this.itemCount,
    required this.dataList,
    required this.projectName,
    required this.onBack,
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
        return GestureDetector(
          onTap: () {
            List<String> allPaths = dataList.map((item) => item['path'] as String).toList();

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ImageView(
                  allImagePaths: allPaths,
                  initialIndex: index,
                  projectName: projectName,
                )
              )
            ).then((_){
              onBack();
            });
          },
          child: ImageCard(imagePath: item['path'],)
        );
      },
      itemCount: dataList.length,
    );
  }
}