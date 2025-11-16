import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GeoVision'),
        shadowColor: Colors.black54,

        backgroundColor: Colors.white,
        elevation: 0.4,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              color: Colors.white,
              height: 150,
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Recent Items',
                    style: TextStyle(
                      fontSize: 15,
                    ),
                  ),
                  SizedBox(height:10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Container(
                          height: 75,
                          width: 75,
                          color: Colors.red,
                        ),
                        SizedBox(width: 5),
                        ...List.generate(6, (index) {
                            return Row(
                              children: [
                                Container(
                                height: 75,
                                width: 75,
                                color: Colors.amber,
                                ),
                                SizedBox(width: 5),
                              ]
                            );
                          },
                        )
                      ],
                    ),
                  )
                ],
              )
            ),
            Container(
              padding: const EdgeInsets.all(20),
              color: Colors.blue,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('All Projects'),
                  SizedBox(height:10),
                  SingleChildScrollView(
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                      ),
                      itemBuilder: (BuildContext context, int index){
                        return Container(
                          height: 5,
                          width: 100,
                          color: Colors.amber,
                        );
                      },
                      itemCount: 6,
                    ),
                  )
                ]
              ),
            ),
            Container(
              color: Colors.green,
              height: 200,
            ),
          ],
        ),
      ),
    );
  }
}
