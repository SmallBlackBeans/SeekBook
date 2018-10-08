// 翻页阅读容器组件

import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart';
import 'package:seek_book/components/read_pager_item.dart';
import 'package:seek_book/utils/screen_adaptation.dart';
import 'package:seek_book/globals.dart' as Globals;

class ReadPager extends StatefulWidget {
  Map bookInfo;

  ReadPager({Key key, @required this.bookInfo}) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _ReadPagerState();
  }
}

int maxInt = 999999;

get ReadTextWidth => ScreenAdaptation.screenWidth - dp(32);

get ReadTextHeight =>
    ScreenAdaptation.screenHeight - dp(35) - dp(44); //减去头部章节名称高度，减去底部页码高度

class _ReadPagerState extends State<ReadPager> {
//  int maxInt = 999999999999999;

  var currentPageIndex = 0;
  var currentChapterIndex = 0;

//  var pageEndIndexList = [];

  Map<String, List> chapterPagerDataMap = Map(); //调整字体后需要清空,url为key
  Map<String, String> chapterTextMap =
      Map(); //章节内容缓存,已缓存到内存的章节，若没有则从网络和本地读取，url为key

//  var content = "";

  get textStyle => new TextStyle(
        height: 1.2,
        fontSize: dp(20),
        letterSpacing: dp(1),
        color: Color(0xff383635),
//        fontFamily: 'ReadFont',
      );

  PageController pageController;

  int initScrollIndex = (maxInt / 2).floor();
  int initPageIndex = 0;
  int initChapterIndex = 0;

  @override
  void initState() {
    this.pageController = PageController(initialPage: initScrollIndex);
    this.pageController.addListener(() {
      var currentPageIndex =
          pageController.page - initScrollIndex + initPageIndex;
      if (currentPageIndex < currentPageIndex.round() &&
          currentPageIndex.round() == 0) {
        print("禁止滑动");
        pageController.jumpToPage(pageController.page.round());
      }
    });
    this.initReadState();
    super.initState();
  }

  initReadState() async {
    this.initPageIndex = widget.bookInfo['currentPageIndex'];
//    this.initPageIndex = 1;
    print("init initPageIndex   $initPageIndex");
    this.loadChapterText(this.initChapterIndex);
  }

  Future loadChapterText(chapterIndex) async {
//    setState(() {
//      this.content = 'loading';
//    });
    var url = widget.bookInfo['chapterList'][chapterIndex]['url'];

    var database = Globals.database;
    List<Map> existData =
        await database.rawQuery('select text from chapter where id = ?', [url]);
    var content = '';
    if (existData.length > 0) {
      content = existData[0]['text'];
    } else {
      Dio dio = new Dio();
//    var url = 'http://www.kenwen.com/cview/241/241355/1371839.html';
      Response response = await dio.get(url);
      var document = parse(response.data);
      content = document.querySelector('#content').innerHtml;
      content = content
          .replaceAll('<script>chaptererror();</script>', '')
          .split("<br>")
          .map((it) => "　　" + it.trim().replaceAll('&nbsp;', ''))
          .where((it) => it.length != 2) //剔除掉只有两个全角空格的行
          .join('\n');
      await database.insert('chapter', {
        "id": url,
        "text": content,
      });
    }
    chapterTextMap[url] = content;

    calcPagerData(url);
//    this.pageEndIndexList = pageEndIndexList;

    setState(() {});
  }

  calcPagerData(url) {
    var exist = chapterPagerDataMap[url];
    if (exist != null) {
      return exist;
    }
    if (chapterTextMap[url] == null) {
      return [0];
    }
    var pageEndIndexList = parseChapterPager(chapterTextMap[url]);
    chapterPagerDataMap[url] = pageEndIndexList;
    print(pageEndIndexList);
    print("页数 ${pageEndIndexList.length}");
    return pageEndIndexList;
  }

  bool onPageScrollNotify(Notification notification) {
//    print(notification.runtimeType);
    if (notification is ScrollEndNotification) {
//      setState(() {
//      var initScrollIndex = pageController.page.round();
//      print(initScrollIndex);
//      });
//      print("xxx");

      var index = pageController.page.round();
      var currentPageIndex = index - initScrollIndex + initPageIndex;
      initScrollIndex = index;
      initPageIndex = currentPageIndex;
      this.saveReadState();
    }
    return false;
  }

  saveReadState() async {
    var database = Globals.database;
    await database.update(
      'Book',
      {
        "currentPageIndex": this.initPageIndex,
      },
      where: "id=?",
      whereArgs: [widget.bookInfo['id']],
    );
    print("asdfsadfasdfasdf ${widget.bookInfo['id']}  ${initPageIndex}");
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener(
      child: new PageView.builder(
        onPageChanged: (index) {
//        print(index);
//        pageController.jumpTo(pageController.offset - 1);
        },
        controller: pageController,
        itemBuilder: (BuildContext context, int index) {
          return buildPage(index);
        },
//      itemCount: 3,
        itemCount: maxInt,
        physics: ClampingScrollPhysics(),
//      physics: PagerScrollPhysics(),
      ),
      onNotification: onPageScrollNotify,
    );
  }

  String loadPageText(url, int pageIndex) {
    var pageEndIndexList = chapterPagerDataMap[url];
    var chapterText = chapterTextMap[url];
    if (pageEndIndexList == null || chapterText == null) {
      return "";
    }
    return chapterText.substring(
      pageIndex == 0 ? 0 : pageEndIndexList[pageIndex - 1],
      pageEndIndexList[pageIndex],
    );
  }

  //测量章节分页逻辑=============⬇=======⬇==========⬇️=============⬇⬇️

  // 解析一个章节所有分页每页最后字符的index列表
  List<int> parseChapterPager(String content) {
    List<int> pageEndPointList = List();
    do {
      var contentNeedToParse = content;
      var prePageEnd = 0;
      if (pageEndPointList.length > 0) {
        prePageEnd = pageEndPointList[pageEndPointList.length - 1];
        contentNeedToParse = content.substring(
          prePageEnd,
          min(prePageEnd + pageEndPointList[0] * 2, content.length),
        );
//        contentNeedToParse = content.substring(prePageEnd);
      }
      pageEndPointList.add(prePageEnd + getOnePageEnd(contentNeedToParse));
    } while (pageEndPointList.length == 0 ||
        pageEndPointList[pageEndPointList.length - 1] != content.length);

    return pageEndPointList;
  }

  /// 传入需要计算分页的文本，返回第一页最后一个字符的index
  int getOnePageEnd(String text) {
    if (layout(text)) {
//      return false;
      return text.length;
    }

    int start = 0;
    int end = text.length;
    int mid = (end + start) ~/ 2;

    var time = 0;
    // 最多循环20次
    for (int i = 0; i < 20; i++) {
      time++;
      if (layout(text.substring(0, mid))) {
        if (mid <= start || mid >= end) break;
        // 未越界
        start = mid;
        mid = (start + end) ~/ 2;
      } else {
        // 越界
        end = mid;
        mid = (start + end) ~/ 2;
      }
    }
//    print('循环次数 ${time}');
    return mid;
  }

  /// 计算待绘制文本
  /// 未超出边界返回true
  /// 超出边界返回false
  bool layout(String text) {
    text = text ?? '';
    var textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter
      ..text = getTextSpan(text)
      ..layout(maxWidth: ReadTextWidth);
    return !didExceed(textPainter);
  }

  /// 是否超出边界
  bool didExceed(textPainter) {
    return textPainter.didExceedMaxLines ||
        textPainter.size.height > ReadTextHeight;
  }

  /// 获取带样式的文本对象
  TextSpan getTextSpan(String text) {
//    if (text.startsWith('\n')) {
//      text = text.substring(1);
//    }
    // 判定时，移除可能是本页文本的最后一个换行符，避免造成超过一页
    if (text.endsWith('\n')) {
      text = text.substring(0, text.length - 1);
    }
    return new TextSpan(text: text, style: textStyle);
  }

  Widget buildPage(int index) {
//    print("MM");
    var pageIndex = initPageIndex + (index - initScrollIndex);
//    print("yyyyy");
//    print(pageIndex);
//    print(initPageIndex);
//    print(index);
//    print(initScrollIndex);

//    var chapterText = chapterTextCacheMap[pageIndex];
    List chapterList = widget.bookInfo['chapterList'];
    var url = chapterList[currentChapterIndex]['url'];
    var chapterText = chapterTextMap[url] ?? '';

    var pageCount = calcPagerData(url).length;
    while (pageIndex > pageCount - 1 && chapterText != '') {
      //翻页超过本章最后一页，加载下一章，并计算页数
      print("NNNNN $pageIndex  , $pageCount ,  $initPageIndex");
      url = chapterList[currentChapterIndex + 1]['url'];
      chapterText = chapterTextMap[url] ?? '';
      var parseChapterPagerList = calcPagerData(url);
      pageCount = parseChapterPagerList.length;
      print(parseChapterPagerList);
      pageIndex -= pageCount;
    }
    while (pageIndex < 0 && chapterText != '') {
      print("PPPPPPPPPPP");
      url = chapterList[currentChapterIndex - 1]['url'];
      chapterText = chapterTextMap[url] ?? '';
      pageCount = calcPagerData(url).length;
      pageIndex += pageCount;
    }
//    print("xxxxxxxxxxx");
//    print(pageIndex);
//    print(pageCount);
//    print('============================');

    var text = "";
    var pageLabel = "";
    var chapterTitle = "";
    var pageEndIndexList = chapterPagerDataMap[url];
    if (pageEndIndexList != null) {
      text = loadPageText(url, pageIndex);
      pageLabel = '${pageIndex + 1}/${pageEndIndexList.length}';
    } else {
      text = "加载中";
    }

    return ReadPagerItem(
      text: new Text(
        text,
        style: textStyle,
      ),
      title: chapterList[initChapterIndex]['title'],
      pageLabel: pageLabel,
    );
  }
}
