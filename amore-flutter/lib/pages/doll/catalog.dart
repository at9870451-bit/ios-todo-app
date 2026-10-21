// Amore 玩偶 Tab — 内置服装目录（与 Doll Studio 3D 同源；后续可经后端 /api/clothes 动态下发）
library;

class DollCloth {
  final String id;
  final String name;
  final String category; // top/bottom/scarf/hat/shoes/hair/accessory
  final String kind; // 程序化模型 kind
  final String color;
  final double price; // 0 = 免费
  final String? exclusiveGroup;

  const DollCloth({
    required this.id,
    required this.name,
    required this.category,
    required this.kind,
    required this.color,
    this.price = 0,
    this.exclusiveGroup,
  });
}

class DollCategory {
  final String key;
  final String title;
  const DollCategory(this.key, this.title);
}

class DollCatalog {
  DollCatalog._();

  static const categories = [
    DollCategory('top', '上衣'),
    DollCategory('bottom', '下装'),
    DollCategory('scarf', '围巾'),
    DollCategory('hat', '帽子'),
    DollCategory('shoes', '鞋子'),
    DollCategory('hair', '发型'),
    DollCategory('accessory', '配饰'),
  ];

  static const clothes = <DollCloth>[
    // 上衣
    DollCloth(id: 'top_tee_white', name: '白色 T 恤', category: 'top', kind: 'tee', color: '#F5F5F7'),
    DollCloth(id: 'top_tee_black', name: '黑色 T 恤', category: 'top', kind: 'tee', color: '#2B2B2E'),
    DollCloth(id: 'top_shirt_blue', name: '蓝色衬衫', category: 'top', kind: 'shirt', color: '#5B8DEF'),
    DollCloth(id: 'top_hoodie_gray', name: '灰色卫衣', category: 'top', kind: 'hoodie', color: '#8E8E93'),
    DollCloth(id: 'top_hoodie_pink', name: '粉色卫衣', category: 'top', kind: 'hoodie', color: '#F4A6C0', price: 6),
    DollCloth(id: 'top_sweater_red', name: '红色毛衣', category: 'top', kind: 'sweater', color: '#C4453C'),
    DollCloth(id: 'top_jacket_denim', name: '牛仔夹克', category: 'top', kind: 'jacket', color: '#4A6B8A', price: 8),
    DollCloth(id: 'top_coat_beige', name: '驼色大衣', category: 'top', kind: 'coat', color: '#C8A882', price: 12),
    // 下装
    DollCloth(id: 'bot_jeans_blue', name: '牛仔裤', category: 'bottom', kind: 'pants', color: '#4A6B9A'),
    DollCloth(id: 'bot_cargo_gray', name: '工装裤', category: 'bottom', kind: 'pants', color: '#7A7A6E'),
    DollCloth(id: 'bot_shorts_beige', name: '休闲短裤', category: 'bottom', kind: 'shorts', color: '#D8C8A8'),
    DollCloth(id: 'bot_skirt_plaid', name: '百褶裙', category: 'bottom', kind: 'skirt', color: '#9A4A5A', price: 6),
    DollCloth(id: 'bot_longskirt_black', name: '黑色长裙', category: 'bottom', kind: 'longskirt', color: '#2B2B2E'),
    // 围巾
    DollCloth(id: 'scarf_knit_gray', name: '深灰针织围巾', category: 'scarf', kind: 'scarf', color: '#5A5A5E'),
    DollCloth(id: 'scarf_long_red', name: '红色长围巾', category: 'scarf', kind: 'scarflong', color: '#B4443C', price: 4),
    DollCloth(id: 'scarf_neck_orange', name: '活力橙围脖', category: 'scarf', kind: 'scarfneck', color: '#FF9500'),
    // 帽子（互斥组 hat）
    DollCloth(id: 'hat_cap_black', name: '黑色棒球帽', category: 'hat', kind: 'cap', color: '#2B2B2E', exclusiveGroup: 'hat'),
    DollCloth(id: 'hat_beanie_knit', name: '针织帽', category: 'hat', kind: 'beanie', color: '#7A5A8A', exclusiveGroup: 'hat'),
    DollCloth(id: 'hat_beret_red', name: '红色贝雷帽', category: 'hat', kind: 'beret', color: '#B4443C', price: 5, exclusiveGroup: 'hat'),
    DollCloth(id: 'hat_bucket_cream', name: '渔夫帽', category: 'hat', kind: 'bucket', color: '#E8DCC8', exclusiveGroup: 'hat'),
    // 鞋子
    DollCloth(id: 'shoe_sneakers_white', name: '白色运动鞋', category: 'shoes', kind: 'sneakers', color: '#F0F0F2'),
    DollCloth(id: 'shoe_leather_black', name: '黑色皮鞋', category: 'shoes', kind: 'leather', color: '#2B2B2E'),
    DollCloth(id: 'shoe_boots_brown', name: '棕色短靴', category: 'shoes', kind: 'boots', color: '#6B4A32', price: 7),
    // 发型
    DollCloth(id: 'hair_short_black', name: '黑色短发', category: 'hair', kind: 'hairShort', color: '#2B2B2E'),
    DollCloth(id: 'hair_long_brown', name: '棕色长发', category: 'hair', kind: 'hairLong', color: '#5A3A28'),
    DollCloth(id: 'hair_curly_gold', name: '金色卷发', category: 'hair', kind: 'hairCurly', color: '#C8A050', price: 5),
    DollCloth(id: 'hair_pony_pink', name: '粉色马尾', category: 'hair', kind: 'hairPony', color: '#E88AA8', price: 5),
    // 配饰
    DollCloth(id: 'acc_glasses_black', name: '黑框眼镜', category: 'accessory', kind: 'glasses', color: '#2B2B2E'),
    DollCloth(id: 'acc_necklace_gold', name: '金色项链', category: 'accessory', kind: 'necklace', color: '#D8B84A', price: 4),
    DollCloth(id: 'acc_bag_brown', name: '棕色挎包', category: 'accessory', kind: 'bag', color: '#6B4A32', price: 5),
    DollCloth(id: 'acc_earring_pearl', name: '珍珠耳饰', category: 'accessory', kind: 'earring', color: '#F0EAE0', price: 3),
  ];

  static DollCloth? byId(String id) {
    for (final c in clothes) {
      if (c.id == id) return c;
    }
    return null;
  }
}
