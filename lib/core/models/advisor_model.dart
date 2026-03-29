import 'package:flutter/material.dart';

/// 助理角色枚举
enum AdvisorCharacter {
  /// 小糖 — 甜美可爱，擅长穿搭
  xiaoTang,

  /// 林晚 — 知性御姐，擅长美妆护肤
  linWan,

  /// 小柚 — 元气阳光，擅长养生
  xiaoYou,

  /// 初夏 — 温柔文艺，擅长生活方式
  chuXia,
}

extension AdvisorCharacterExt on AdvisorCharacter {
  String get name {
    switch (this) {
      case AdvisorCharacter.xiaoTang:
        return '小糖';
      case AdvisorCharacter.linWan:
        return '林晚';
      case AdvisorCharacter.xiaoYou:
        return '小柚';
      case AdvisorCharacter.chuXia:
        return '初夏';
    }
  }

  String get personality {
    switch (this) {
      case AdvisorCharacter.xiaoTang:
        return '活泼可爱，爱撒娇，穿搭达人';
      case AdvisorCharacter.linWan:
        return '冷静专业，有品位，美妆护肤专家';
      case AdvisorCharacter.xiaoYou:
        return '阳光开朗，健康生活方式倡导者';
      case AdvisorCharacter.chuXia:
        return '温柔慢热，生活美学家';
    }
  }

  String get greeting {
    switch (this) {
      case AdvisorCharacter.xiaoTang:
        return '嗨嗨嗨！今天想穿什么风格呀～';
      case AdvisorCharacter.linWan:
        return '你好，今天想了解什么？';
      case AdvisorCharacter.xiaoYou:
        return '早～今天也要元气满满哦！';
      case AdvisorCharacter.chuXia:
        return '嗯，今天过得怎么样？';
    }
  }

  /// 对应的占位颜色（模型加载前显示）
  String get themeColor {
    switch (this) {
      case AdvisorCharacter.xiaoTang:
        return '#FFB5C8'; // 粉色
      case AdvisorCharacter.linWan:
        return '#B5C8D4'; // 冷蓝灰
      case AdvisorCharacter.xiaoYou:
        return '#C8D4B5'; // 青绿
      case AdvisorCharacter.chuXia:
        return '#D4C8B5'; // 暖米
    }
  }

  /// 主色（Flutter Color，用于渐变/光晕）
  Color get primaryColor {
    switch (this) {
      case AdvisorCharacter.xiaoTang:
        return const Color(0xFFFFB5C8);
      case AdvisorCharacter.linWan:
        return const Color(0xFF8BA5C8);
      case AdvisorCharacter.xiaoYou:
        return const Color(0xFF8DC8A0);
      case AdvisorCharacter.chuXia:
        return const Color(0xFFC9956C);
    }
  }

  /// 次色（用于渐变底色）
  Color get secondaryColor {
    switch (this) {
      case AdvisorCharacter.xiaoTang:
        return const Color(0xFFE891AC);
      case AdvisorCharacter.linWan:
        return const Color(0xFF5A7999);
      case AdvisorCharacter.xiaoYou:
        return const Color(0xFF5DA876);
      case AdvisorCharacter.chuXia:
        return const Color(0xFFA87550);
    }
  }
}

/// 助理状态枚举（驱动人物动画）
enum AdvisorState {
  /// 待机：呼吸浮动，偶尔眨眼
  idle,

  /// 倾听中：侧耳，眼睛注视
  listening,

  /// 思考中：托腮，粒子飘动
  thinking,

  /// 说话中：活泼表达
  speaking,

  /// 开心：跳跃/庆祝
  happy,

  /// 好奇：歪头看
  curious,

  /// 扫描中（分析图片时）
  scanning,
}
