# TOON Format Encoding Showcase

This document demonstrates how the TOON format encodes various data structures compared to their original JSON representation.

---

## 1. Basic Object

**Original JSON:**
```json
{
  "name": "Alice",
  "age": 30
}
```

**TOON Encoded:**
```
name: Alice
age: 30
```

---

## 2. Basic Array

**Original JSON:**
```json
[
  1,
  2,
  3
]
```

**TOON Encoded:**
```
[3]: 1,2,3
```

---

## 3. Nested Object

**Original JSON:**
```json
{
  "user": {
    "name": "Bob",
    "contact": {
      "email": "bob@ex.com"
    }
  }
}
```

**TOON Encoded:**
```
user:
  name: Bob
  contact:
    email: bob@ex.com
```

---

## 4. Empty Collections

**Original JSON:**
```json
{
  "data": [],
  "metadata": {}
}
```

**TOON Encoded:**
```
data[0]:
metadata:
```

---

## 5. Null and Undefined Values

**Original JSON:**
```json
{
  "a": null
}
```

**TOON Encoded:**
```
a: null
b: null
```

---

## 6. Mixed Types

**Original JSON:**
```json
{
  "str": "text",
  "num": 42,
  "bool": true,
  "nil": null,
  "arr": [
    1,
    "two"
  ]
}
```

**TOON Encoded:**
```
str: text
num: 42
bool: true
nil: null
arr[2]: 1,two
```

---

## 7. Special Characters

**Original JSON:**
```json
{
  "text": "He said \"hello\"",
  "path": "C:\\Users\\file",
  "newline": "line1\nline2"
}
```

**TOON Encoded:**
```
text: "He said \"hello\""
path: "C:\\Users\\file"
newline: "line1\nline2"
```

---

## 8. Numbers

**Original JSON:**
```json
{
  "zero": 0,
  "negative": -5,
  "float": 3.14,
  "large": 9007199254740991
}
```

**TOON Encoded:**
```
zero: 0
negative: -5
float: 3.14
large: 9007199254740991
```

---

## 9. Strings

**Original JSON:**
```json
{
  "empty": "",
  "space": " ",
  "tab": "\t"
}
```

**TOON Encoded:**
```
empty: ""
space: " "
tab: "\t"
```

---

## 10. Deeply Nested Structure

**Original JSON:**
```json
{
  "a": {
    "b": {
      "c": {
        "d": {
          "e": "value"
        }
      }
    }
  }
}
```

**TOON Encoded:**
```
a:
  b:
    c:
      d:
        e: value
```

---

## 11. Large Array

**Original JSON:**
```json
{
  "items": [
    0,
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20,
    21,
    22,
    23,
    24,
    25,
    26,
    27,
    28,
    29,
    30,
    31,
    32,
    33,
    34,
    35,
    36,
    37,
    38,
    39,
    40,
    41,
    42,
    43,
    44,
    45,
    46,
    47,
    48,
    49,
    50,
    51,
    52,
    53,
    54,
    55,
    56,
    57,
    58,
    59,
    60,
    61,
    62,
    63,
    64,
    65,
    66,
    67,
    68,
    69,
    70,
    71,
    72,
    73,
    74,
    75,
    76,
    77,
    78,
    79,
    80,
    81,
    82,
    83,
    84,
    85,
    86,
    87,
    88,
    89,
    90,
    91,
    92,
    93,
    94,
    95,
    96,
    97,
    98,
    99
  ]
}
```

**TOON Encoded:**
```
items[100]: 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99
```

---

## 12. Booleans

**Original JSON:**
```json
{
  "t": true,
  "f": false
}
```

**TOON Encoded:**
```
t: true
f: false
```

---

## 13. Unicode Characters

**Original JSON:**
```json
{
  "greeting": "こんにちは",
  "emoji": "🚀",
  "symbol": "€"
}
```

**TOON Encoded:**
```
greeting: こんにちは
emoji: 🚀
symbol: €
```

---

## 14. API Response

**Original JSON:**
```json
{
  "status": 200,
  "data": {
    "id": 1,
    "name": "Test"
  },
  "errors": null
}
```

**TOON Encoded:**
```
status: 200
data:
  id: 1
  name: Test
errors: null
```

---

## 15. Records (Array of Objects)

**Original JSON:**
```json
[
  {
    "id": 1,
    "active": true
  },
  {
    "id": 2,
    "active": false
  }
]
```

**TOON Encoded:**
```
[2]{id,active}:
  1,true
  2,false
```

---

## 16. Irregular Array

**Original JSON:**
```json
[
  {
    "a": 1
  },
  {
    "a": 1,
    "b": 2
  },
  {
    "c": 3
  }
]
```

**TOON Encoded:**
```
[3]:
  - a: 1
  - a: 1
    b: 2
  - c: 3
```

---

## 17. Array of Arrays

**Original JSON:**
```json
[
  [
    1,
    2,
    3
  ],
  [
    "a",
    "b",
    "c"
  ],
  [
    true,
    false,
    true
  ]
]
```

**TOON Encoded:**
```
[3]:
  - [3]: 1,2,3
  - [3]: a,b,c
  - [3]: true,false,true
```

---

## 18. Nested Mixed Types

**Original JSON:**
```json
{
  "items": [
    {
      "users": [
        {
          "id": 1,
          "name": "Ada"
        },
        {
          "id": 2,
          "name": "Bob"
        }
      ],
      "status": "active"
    }
  ]
}
```

**TOON Encoded:**
```
items[1]:
  - users[2]{id,name}:
    1,Ada
    2,Bob
    status: active
```

---

## 19. Glossary Structure

**Original JSON:**
```json
{
  "glossary": {
    "title": "example glossary",
    "GlossDiv": {
      "title": "S",
      "GlossList": {
        "GlossEntry": {
          "ID": "SGML",
          "SortAs": "SGML",
          "GlossTerm": "Standard Generalized Markup Language",
          "Acronym": "SGML",
          "Abbrev": "ISO 8879:1986",
          "GlossDef": {
            "para": "A meta-markup language, used to create markup languages such as DocBook.",
            "GlossSeeAlso": [
              "GML",
              "XML"
            ]
          },
          "GlossSee": "markup"
        }
      }
    }
  }
}
```

**TOON Encoded:**
```
glossary:
  title: example glossary
  GlossDiv:
    title: S
    GlossList:
      GlossEntry:
        ID: SGML
        SortAs: SGML
        GlossTerm: Standard Generalized Markup Language
        Acronym: SGML
        Abbrev: "ISO 8879:1986"
        GlossDef:
          para: "A meta-markup language, used to create markup languages such as DocBook."
          GlossSeeAlso[2]: GML,XML
        GlossSee: markup
```

---

## 20. Countries Data Set

**Original JSON:**
```json
[
  {
    "name": "France",
    "capital": "Paris",
    "population": 67364357,
    "area": 551695,
    "currency": "Euro",
    "languages": [
      "French"
    ],
    "region": "Europe",
    "subregion": "Western Europe",
    "flag": "https://upload.wikimedia.org/wikipedia/commons/c/c3/Flag_of_France.svg"
  },
  {
    "name": "Germany",
    "capital": "Berlin",
    "population": 83240525,
    "area": 357022,
    "currency": "Euro",
    "languages": [
      "German"
    ],
    "region": "Europe",
    "subregion": "Western Europe",
    "flag": "https://upload.wikimedia.org/wikipedia/commons/b/ba/Flag_of_Germany.svg"
  },
  {
    "name": "United States",
    "capital": "Washington, D.C.",
    "population": 331893745,
    "area": 9833517,
    "currency": "USD",
    "languages": [
      "English"
    ],
    "region": "Americas",
    "subregion": "Northern America",
    "flag": "https://upload.wikimedia.org/wikipedia/commons/a/a4/Flag_of_the_United_States.svg"
  },
  {
    "name": "Belgium",
    "capital": "Brussels",
    "population": 11589623,
    "area": 30528,
    "currency": "Euro",
    "languages": [
      "Flemish",
      "French",
      "German"
    ],
    "region": "Europe",
    "subregion": "Western Europe",
    "flag": "https://upload.wikimedia.org/wikipedia/commons/6/65/Flag_of_Belgium.svg"
  }
]
```

**TOON Encoded:**
```
[4]:
  - name: France
    capital: Paris
    population: 67364357
    area: 551695
    currency: Euro
    languages[1]: French
    region: Europe
    subregion: Western Europe
    flag: "https://upload.wikimedia.org/wikipedia/commons/c/c3/Flag_of_France.svg"
  - name: Germany
    capital: Berlin
    population: 83240525
    area: 357022
    currency: Euro
    languages[1]: German
    region: Europe
    subregion: Western Europe
    flag: "https://upload.wikimedia.org/wikipedia/commons/b/ba/Flag_of_Germany.svg"
  - name: United States
    capital: "Washington, D.C."
    population: 331893745
    area: 9833517
    currency: USD
    languages[1]: English
    region: Americas
    subregion: Northern America
    flag: "https://upload.wikimedia.org/wikipedia/commons/a/a4/Flag_of_the_United_States.svg"
  - name: Belgium
    capital: Brussels
    population: 11589623
    area: 30528
    currency: Euro
    languages[3]: Flemish,French,German
    region: Europe
    subregion: Western Europe
    flag: "https://upload.wikimedia.org/wikipedia/commons/6/65/Flag_of_Belgium.svg"
```

---

## 21. E-commerce Product Catalog

**Original JSON:**
```json
[
  {
    "productId": 1001,
    "productName": "Wireless Headphones",
    "description": "Noise-cancelling wireless headphones with Bluetooth 5.0 and 20-hour battery life.",
    "brand": "SoundPro",
    "category": "Electronics",
    "price": 199.99,
    "currency": "USD",
    "stock": {
      "available": true,
      "quantity": 50
    },
    "images": [
      "https://example.com/products/1001/main.jpg",
      "https://example.com/products/1001/side.jpg"
    ],
    "variants": [
      {
        "variantId": "1001_01",
        "color": "Black",
        "price": 199.99,
        "stockQuantity": 20
      },
      {
        "variantId": "1001_02",
        "color": "White",
        "price": 199.99,
        "stockQuantity": 30
      }
    ],
    "dimensions": {
      "weight": "0.5kg",
      "width": "18cm",
      "height": "20cm",
      "depth": "8cm"
    },
    "ratings": {
      "averageRating": 4.7,
      "numberOfReviews": 120
    },
    "reviews": [
      {
        "reviewId": 501,
        "userId": 101,
        "username": "techguy123",
        "rating": 5,
        "comment": "Amazing sound quality and battery life!"
      },
      {
        "reviewId": 502,
        "userId": 102,
        "username": "jane_doe",
        "rating": 4,
        "comment": "Great headphones but a bit pricey."
      }
    ]
  },
  {
    "productId": 1002,
    "productName": "Smartphone Case",
    "description": "Durable and shockproof case for smartphones, available in multiple colors.",
    "brand": "CaseMate",
    "category": "Accessories",
    "price": 29.99,
    "currency": "USD",
    "stock": {
      "available": true,
      "quantity": 200
    },
    "images": [
      "https://example.com/products/1002/main.jpg",
      "https://example.com/products/1002/back.jpg"
    ],
    "variants": [
      {
        "variantId": "1002_01",
        "color": "Black",
        "price": 29.99,
        "stockQuantity": 100
      },
      {
        "variantId": "1002_02",
        "color": "Blue",
        "price": 29.99,
        "stockQuantity": 100
      }
    ],
    "dimensions": {
      "weight": "0.2kg",
      "width": "8cm",
      "height": "15cm",
      "depth": "1cm"
    },
    "ratings": {
      "averageRating": 4.4,
      "numberOfReviews": 80
    },
    "reviews": [
      {
        "reviewId": 601,
        "userId": 103,
        "username": "caseuser456",
        "rating": 4,
        "comment": "Very sturdy and fits perfectly."
      },
      {
        "reviewId": 602,
        "userId": 104,
        "username": "mobile_fan",
        "rating": 5,
        "comment": "Best case I've bought for my phone!"
      }
    ]
  },
  {
    "productId": 1003,
    "productName": "4K Ultra HD Smart TV",
    "description": "55-inch 4K Ultra HD Smart TV with built-in Wi-Fi and streaming apps.",
    "brand": "Visionary",
    "category": "Electronics",
    "price": 799.99,
    "currency": "USD",
    "stock": {
      "available": true,
      "quantity": 30
    },
    "images": [
      "https://example.com/products/1003/main.jpg",
      "https://example.com/products/1003/side.jpg"
    ],
    "variants": [
      {
        "variantId": "1003_01",
        "screenSize": "55 inch",
        "price": 799.99,
        "stockQuantity": 30
      }
    ],
    "dimensions": {
      "weight": "15kg",
      "width": "123cm",
      "height": "80cm",
      "depth": "10cm"
    },
    "ratings": {
      "averageRating": 4.8,
      "numberOfReviews": 250
    },
    "reviews": [
      {
        "reviewId": 701,
        "userId": 105,
        "username": "techlover123",
        "rating": 5,
        "comment": "Incredible picture quality, streaming works seamlessly."
      },
      {
        "reviewId": 702,
        "userId": 106,
        "username": "homecinema",
        "rating": 4,
        "comment": "Great TV, but a little bulky."
      }
    ]
  },
  {
    "productId": 1004,
    "productName": "Bluetooth Speaker",
    "description": "Portable Bluetooth speaker with 12-hour battery life and water resistance.",
    "brand": "AudioX",
    "category": "Electronics",
    "price": 59.99,
    "currency": "USD",
    "stock": {
      "available": true,
      "quantity": 100
    },
    "images": [
      "https://example.com/products/1004/main.jpg",
      "https://example.com/products/1004/side.jpg"
    ],
    "variants": [
      {
        "variantId": "1004_01",
        "color": "Red",
        "price": 59.99,
        "stockQuantity": 50
      },
      {
        "variantId": "1004_02",
        "color": "Blue",
        "price": 59.99,
        "stockQuantity": 50
      }
    ],
    "dimensions": {
      "weight": "0.3kg",
      "width": "15cm",
      "height": "8cm",
      "depth": "5cm"
    },
    "ratings": {
      "averageRating": 4.6,
      "numberOfReviews": 150
    },
    "reviews": [
      {
        "reviewId": 801,
        "userId": 107,
        "username": "musicfan23",
        "rating": 5,
        "comment": "Excellent sound quality for its size!"
      },
      {
        "reviewId": 802,
        "userId": 108,
        "username": "outdoor_lover",
        "rating": 4,
        "comment": "Great for outdoor use, but the battery could last longer."
      }
    ]
  },
  {
    "productId": 1005,
    "productName": "Winter Jacket",
    "description": "Men's water-resistant winter jacket with a fur-lined hood.",
    "brand": "ColdTech",
    "category": "Clothing",
    "price": 129.99,
    "currency": "USD",
    "stock": {
      "available": true,
      "quantity": 80
    },
    "images": [
      "https://example.com/products/1005/main.jpg",
      "https://example.com/products/1005/back.jpg"
    ],
    "variants": [
      {
        "variantId": "1005_01",
        "size": "M",
        "color": "Black",
        "price": 129.99,
        "stockQuantity": 30
      },
      {
        "variantId": "1005_02",
        "size": "L",
        "color": "Gray",
        "price": 129.99,
        "stockQuantity": 50
      }
    ],
    "dimensions": {
      "weight": "1.5kg",
      "width": "60cm",
      "height": "85cm",
      "depth": "5cm"
    },
    "ratings": {
      "averageRating": 4.5,
      "numberOfReviews": 60
    },
    "reviews": [
      {
        "reviewId": 901,
        "userId": 109,
        "username": "outdoor_adventurer",
        "rating": 5,
        "comment": "Perfect for cold weather, very comfortable!"
      },
      {
        "reviewId": 902,
        "userId": 110,
        "username": "winter_gear",
        "rating": 4,
        "comment": "Nice jacket, but could be a little warmer."
      }
    ]
  }
]
```

**TOON Encoded:**
```
[5]:
  - productId: 1001
    productName: Wireless Headphones
    description: Noise-cancelling wireless headphones with Bluetooth 5.0 and 20-hour battery life.
    brand: SoundPro
    category: Electronics
    price: 199.99
    currency: USD
    stock:
      available: true
      quantity: 50
    images[2]: "https://example.com/products/1001/main.jpg","https://example.com/products/1001/side.jpg"
    variants[2]{variantId,color,price,stockQuantity}:
      1001_01,Black,199.99,20
      1001_02,White,199.99,30
    dimensions:
      weight: 0.5kg
      width: 18cm
      height: 20cm
      depth: 8cm
    ratings:
      averageRating: 4.7
      numberOfReviews: 120
    reviews[2]{reviewId,userId,username,rating,comment}:
      501,101,techguy123,5,Amazing sound quality and battery life!
      502,102,jane_doe,4,Great headphones but a bit pricey.
  - productId: 1002
    productName: Smartphone Case
    description: "Durable and shockproof case for smartphones, available in multiple colors."
    brand: CaseMate
    category: Accessories
    price: 29.99
    currency: USD
    stock:
      available: true
      quantity: 200
    images[2]: "https://example.com/products/1002/main.jpg","https://example.com/products/1002/back.jpg"
    variants[2]{variantId,color,price,stockQuantity}:
      1002_01,Black,29.99,100
      1002_02,Blue,29.99,100
    dimensions:
      weight: 0.2kg
      width: 8cm
      height: 15cm
      depth: 1cm
    ratings:
      averageRating: 4.4
      numberOfReviews: 80
    reviews[2]{reviewId,userId,username,rating,comment}:
      601,103,caseuser456,4,Very sturdy and fits perfectly.
      602,104,mobile_fan,5,Best case I've bought for my phone!
  - productId: 1003
    productName: 4K Ultra HD Smart TV
    description: 55-inch 4K Ultra HD Smart TV with built-in Wi-Fi and streaming apps.
    brand: Visionary
    category: Electronics
    price: 799.99
    currency: USD
    stock:
      available: true
      quantity: 30
    images[2]: "https://example.com/products/1003/main.jpg","https://example.com/products/1003/side.jpg"
    variants[1]{variantId,screenSize,price,stockQuantity}:
      1003_01,55 inch,799.99,30
    dimensions:
      weight: 15kg
      width: 123cm
      height: 80cm
      depth: 10cm
    ratings:
      averageRating: 4.8
      numberOfReviews: 250
    reviews[2]{reviewId,userId,username,rating,comment}:
      701,105,techlover123,5,"Incredible picture quality, streaming works seamlessly."
      702,106,homecinema,4,"Great TV, but a little bulky."
  - productId: 1004
    productName: Bluetooth Speaker
    description: Portable Bluetooth speaker with 12-hour battery life and water resistance.
    brand: AudioX
    category: Electronics
    price: 59.99
    currency: USD
    stock:
      available: true
      quantity: 100
    images[2]: "https://example.com/products/1004/main.jpg","https://example.com/products/1004/side.jpg"
    variants[2]{variantId,color,price,stockQuantity}:
      1004_01,Red,59.99,50
      1004_02,Blue,59.99,50
    dimensions:
      weight: 0.3kg
      width: 15cm
      height: 8cm
      depth: 5cm
    ratings:
      averageRating: 4.6
      numberOfReviews: 150
    reviews[2]{reviewId,userId,username,rating,comment}:
      801,107,musicfan23,5,Excellent sound quality for its size!
      802,108,outdoor_lover,4,"Great for outdoor use, but the battery could last longer."
  - productId: 1005
    productName: Winter Jacket
    description: Men's water-resistant winter jacket with a fur-lined hood.
    brand: ColdTech
    category: Clothing
    price: 129.99
    currency: USD
    stock:
      available: true
      quantity: 80
    images[2]: "https://example.com/products/1005/main.jpg","https://example.com/products/1005/back.jpg"
    variants[2]{variantId,size,color,price,stockQuantity}:
      1005_01,M,Black,129.99,30
      1005_02,L,Gray,129.99,50
    dimensions:
      weight: 1.5kg
      width: 60cm
      height: 85cm
      depth: 5cm
    ratings:
      averageRating: 4.5
      numberOfReviews: 60
    reviews[2]{reviewId,userId,username,rating,comment}:
      901,109,outdoor_adventurer,5,"Perfect for cold weather, very comfortable!"
      902,110,winter_gear,4,"Nice jacket, but could be a little warmer."
```

---

## Key TOON Features Demonstrated

- **Compact Array Syntax:** `[length]: elements` for homogeneous arrays
- **Key-Value Pairs:** Simple `key: value` format
- **Indentation:** Nested structures use indentation instead of braces
- **Columnar Format:** Homogeneous object arrays use column headers and comma-separated values
- **Special Character Handling:** Quotes and escapes are preserved
- **Unicode Support:** Full support for international characters and emojis
- **Null Handling:** Treats both `null` and `undefined` as `null`
- **Type Preservation:** Numbers, booleans, and strings maintain their types
