import { encode } from "@toon-format/toon";
import { writeFileSync } from "fs";
import { join } from "path";

const basicObject = { name: "Alice", age: 30 };
const basicArr = [1, 2, 3];
const basicNestedObject = {
  user: { name: "Bob", contact: { email: "bob@ex.com" } },
};

const empty = { data: [], metadata: {} };
const nullValues = { a: null, b: undefined };
const mixed = { str: "text", num: 42, bool: true, nil: null, arr: [1, "two"] };
const specialChars = {
  text: 'He said "hello"',
  path: "C:\\Users\\file",
  newline: "line1\nline2",
};
const numbers = { zero: 0, negative: -5, float: 3.14, large: 9007199254740991 };
const strings = { empty: "", space: " ", tab: "\t" };
const deeplyNested = { a: { b: { c: { d: { e: "value" } } } } };
const largeArr = { items: Array.from({ length: 100 }, (_, i) => i) };
const booleans = { t: true, f: false };
const unicode = { greeting: "こんにちは", emoji: "🚀", symbol: "€" };

const apiResponse = {
  status: 200,
  data: { id: 1, name: "Test" },
  errors: null,
};

const records = [
  { id: 1, active: true },
  { id: 2, active: false },
];

const irregular = [{ a: 1 }, { a: 1, b: 2 }, { c: 3 }];

const arrayOfArrays = [
  [1, 2, 3],
  ["a", "b", "c"],
  [true, false, true],
];

const nestedMixed = {
  items: [
    {
      users: [
        { id: 1, name: "Ada" },
        { id: 2, name: "Bob" },
      ],
      status: "active",
    },
  ],
};

const glossary = {
  glossary: {
    title: "example glossary",
    GlossDiv: {
      title: "S",
      GlossList: {
        GlossEntry: {
          ID: "SGML",
          SortAs: "SGML",
          GlossTerm: "Standard Generalized Markup Language",
          Acronym: "SGML",
          Abbrev: "ISO 8879:1986",
          GlossDef: {
            para: "A meta-markup language, used to create markup languages such as DocBook.",
            GlossSeeAlso: ["GML", "XML"],
          },
          GlossSee: "markup",
        },
      },
    },
  },
};

const countriesArr = [
  {
    name: "France",
    capital: "Paris",
    population: 67364357,
    area: 551695,
    currency: "Euro",
    languages: ["French"],
    region: "Europe",
    subregion: "Western Europe",
    flag: "https://upload.wikimedia.org/wikipedia/commons/c/c3/Flag_of_France.svg",
  },
  {
    name: "Germany",
    capital: "Berlin",
    population: 83240525,
    area: 357022,
    currency: "Euro",
    languages: ["German"],
    region: "Europe",
    subregion: "Western Europe",
    flag: "https://upload.wikimedia.org/wikipedia/commons/b/ba/Flag_of_Germany.svg",
  },
  {
    name: "United States",
    capital: "Washington, D.C.",
    population: 331893745,
    area: 9833517,
    currency: "USD",
    languages: ["English"],
    region: "Americas",
    subregion: "Northern America",
    flag: "https://upload.wikimedia.org/wikipedia/commons/a/a4/Flag_of_the_United_States.svg",
  },
  {
    name: "Belgium",
    capital: "Brussels",
    population: 11589623,
    area: 30528,
    currency: "Euro",
    languages: ["Flemish", "French", "German"],
    region: "Europe",
    subregion: "Western Europe",
    flag: "https://upload.wikimedia.org/wikipedia/commons/6/65/Flag_of_Belgium.svg",
  },
];

const products = [
  {
    productId: 1001,
    productName: "Wireless Headphones",
    description:
      "Noise-cancelling wireless headphones with Bluetooth 5.0 and 20-hour battery life.",
    brand: "SoundPro",
    category: "Electronics",
    price: 199.99,
    currency: "USD",
    stock: {
      available: true,
      quantity: 50,
    },
    images: [
      "https://example.com/products/1001/main.jpg",
      "https://example.com/products/1001/side.jpg",
    ],
    variants: [
      {
        variantId: "1001_01",
        color: "Black",
        price: 199.99,
        stockQuantity: 20,
      },
      {
        variantId: "1001_02",
        color: "White",
        price: 199.99,
        stockQuantity: 30,
      },
    ],
    dimensions: {
      weight: "0.5kg",
      width: "18cm",
      height: "20cm",
      depth: "8cm",
    },
    ratings: {
      averageRating: 4.7,
      numberOfReviews: 120,
    },
    reviews: [
      {
        reviewId: 501,
        userId: 101,
        username: "techguy123",
        rating: 5,
        comment: "Amazing sound quality and battery life!",
      },
      {
        reviewId: 502,
        userId: 102,
        username: "jane_doe",
        rating: 4,
        comment: "Great headphones but a bit pricey.",
      },
    ],
  },
  {
    productId: 1002,
    productName: "Smartphone Case",
    description:
      "Durable and shockproof case for smartphones, available in multiple colors.",
    brand: "CaseMate",
    category: "Accessories",
    price: 29.99,
    currency: "USD",
    stock: {
      available: true,
      quantity: 200,
    },
    images: [
      "https://example.com/products/1002/main.jpg",
      "https://example.com/products/1002/back.jpg",
    ],
    variants: [
      {
        variantId: "1002_01",
        color: "Black",
        price: 29.99,
        stockQuantity: 100,
      },
      {
        variantId: "1002_02",
        color: "Blue",
        price: 29.99,
        stockQuantity: 100,
      },
    ],
    dimensions: {
      weight: "0.2kg",
      width: "8cm",
      height: "15cm",
      depth: "1cm",
    },
    ratings: {
      averageRating: 4.4,
      numberOfReviews: 80,
    },
    reviews: [
      {
        reviewId: 601,
        userId: 103,
        username: "caseuser456",
        rating: 4,
        comment: "Very sturdy and fits perfectly.",
      },
      {
        reviewId: 602,
        userId: 104,
        username: "mobile_fan",
        rating: 5,
        comment: "Best case I've bought for my phone!",
      },
    ],
  },
  {
    productId: 1003,
    productName: "4K Ultra HD Smart TV",
    description:
      "55-inch 4K Ultra HD Smart TV with built-in Wi-Fi and streaming apps.",
    brand: "Visionary",
    category: "Electronics",
    price: 799.99,
    currency: "USD",
    stock: {
      available: true,
      quantity: 30,
    },
    images: [
      "https://example.com/products/1003/main.jpg",
      "https://example.com/products/1003/side.jpg",
    ],
    variants: [
      {
        variantId: "1003_01",
        screenSize: "55 inch",
        price: 799.99,
        stockQuantity: 30,
      },
    ],
    dimensions: {
      weight: "15kg",
      width: "123cm",
      height: "80cm",
      depth: "10cm",
    },
    ratings: {
      averageRating: 4.8,
      numberOfReviews: 250,
    },
    reviews: [
      {
        reviewId: 701,
        userId: 105,
        username: "techlover123",
        rating: 5,
        comment: "Incredible picture quality, streaming works seamlessly.",
      },
      {
        reviewId: 702,
        userId: 106,
        username: "homecinema",
        rating: 4,
        comment: "Great TV, but a little bulky.",
      },
    ],
  },
  {
    productId: 1004,
    productName: "Bluetooth Speaker",
    description:
      "Portable Bluetooth speaker with 12-hour battery life and water resistance.",
    brand: "AudioX",
    category: "Electronics",
    price: 59.99,
    currency: "USD",
    stock: {
      available: true,
      quantity: 100,
    },
    images: [
      "https://example.com/products/1004/main.jpg",
      "https://example.com/products/1004/side.jpg",
    ],
    variants: [
      {
        variantId: "1004_01",
        color: "Red",
        price: 59.99,
        stockQuantity: 50,
      },
      {
        variantId: "1004_02",
        color: "Blue",
        price: 59.99,
        stockQuantity: 50,
      },
    ],
    dimensions: {
      weight: "0.3kg",
      width: "15cm",
      height: "8cm",
      depth: "5cm",
    },
    ratings: {
      averageRating: 4.6,
      numberOfReviews: 150,
    },
    reviews: [
      {
        reviewId: 801,
        userId: 107,
        username: "musicfan23",
        rating: 5,
        comment: "Excellent sound quality for its size!",
      },
      {
        reviewId: 802,
        userId: 108,
        username: "outdoor_lover",
        rating: 4,
        comment: "Great for outdoor use, but the battery could last longer.",
      },
    ],
  },
  {
    productId: 1005,
    productName: "Winter Jacket",
    description: "Men's water-resistant winter jacket with a fur-lined hood.",
    brand: "ColdTech",
    category: "Clothing",
    price: 129.99,
    currency: "USD",
    stock: {
      available: true,
      quantity: 80,
    },
    images: [
      "https://example.com/products/1005/main.jpg",
      "https://example.com/products/1005/back.jpg",
    ],
    variants: [
      {
        variantId: "1005_01",
        size: "M",
        color: "Black",
        price: 129.99,
        stockQuantity: 30,
      },
      {
        variantId: "1005_02",
        size: "L",
        color: "Gray",
        price: 129.99,
        stockQuantity: 50,
      },
    ],
    dimensions: {
      weight: "1.5kg",
      width: "60cm",
      height: "85cm",
      depth: "5cm",
    },
    ratings: {
      averageRating: 4.5,
      numberOfReviews: 60,
    },
    reviews: [
      {
        reviewId: 901,
        userId: 109,
        username: "outdoor_adventurer",
        rating: 5,
        comment: "Perfect for cold weather, very comfortable!",
      },
      {
        reviewId: 902,
        userId: 110,
        username: "winter_gear",
        rating: 4,
        comment: "Nice jacket, but could be a little warmer.",
      },
    ],
  },
];

// Define test cases with descriptions
const testCases: Array<{
  name: string;
  value: unknown;
  description: string;
}> = [
  { name: "basicObject", value: basicObject, description: "Basic Object" },
  { name: "basicArr", value: basicArr, description: "Basic Array" },
  {
    name: "basicNestedObject",
    value: basicNestedObject,
    description: "Nested Object",
  },
  { name: "empty", value: empty, description: "Empty Collections" },
  {
    name: "nullValues",
    value: nullValues,
    description: "Null and Undefined Values",
  },
  { name: "mixed", value: mixed, description: "Mixed Types" },
  {
    name: "specialChars",
    value: specialChars,
    description: "Special Characters",
  },
  { name: "numbers", value: numbers, description: "Numbers" },
  { name: "strings", value: strings, description: "Strings" },
  {
    name: "deeplyNested",
    value: deeplyNested,
    description: "Deeply Nested Structure",
  },
  { name: "largeArr", value: largeArr, description: "Large Array" },
  { name: "booleans", value: booleans, description: "Booleans" },
  { name: "unicode", value: unicode, description: "Unicode Characters" },
  { name: "apiResponse", value: apiResponse, description: "API Response" },
  {
    name: "records",
    value: records,
    description: "Records (Array of Objects)",
  },
  {
    name: "irregular",
    value: irregular,
    description: "Irregular Array",
  },
  {
    name: "arrayOfArrays",
    value: arrayOfArrays,
    description: "Array of Arrays",
  },
  {
    name: "nestedMixed",
    value: nestedMixed,
    description: "Nested Mixed Types",
  },
  {
    name: "glossary",
    value: glossary,
    description: "Glossary Structure",
  },
  {
    name: "countriesArr",
    value: countriesArr,
    description: "Countries Data Set",
  },
  {
    name: "products",
    value: products,
    description: "E-commerce Product Catalog",
  },
];

// Generate markdown
function generateMarkdown(): string {
  let markdown = `# TOON Format Encoding Showcase

This document demonstrates how the TOON format encodes various data structures compared to their original JSON representation.

---

`;

  testCases.forEach((testCase, index) => {
    const jsonStr = JSON.stringify(testCase.value, null, 2);
    const toonStr = encode(testCase.value, { indent: 2 });

    markdown += `## ${index + 1}. ${testCase.description}

**Original JSON:**
\`\`\`json
${jsonStr}
\`\`\`

**TOON Encoded:**
\`\`\`
${toonStr}
\`\`\`

---

`;
  });

  markdown += `## Key TOON Features Demonstrated

- **Compact Array Syntax:** \`[length]: elements\` for homogeneous arrays
- **Key-Value Pairs:** Simple \`key: value\` format
- **Indentation:** Nested structures use indentation instead of braces
- **Columnar Format:** Homogeneous object arrays use column headers and comma-separated values
- **Special Character Handling:** Quotes and escapes are preserved
- **Unicode Support:** Full support for international characters and emojis
- **Null Handling:** Treats both \`null\` and \`undefined\` as \`null\`
- **Type Preservation:** Numbers, booleans, and strings maintain their types
`;

  return markdown;
}

// Write markdown file
const markdown = generateMarkdown();
const outputPath = join(import.meta.dir, "ENCODING_SHOWCASE.md");
writeFileSync(outputPath, markdown, "utf-8");

console.log(`✓ Generated ENCODING_SHOWCASE.md`);
console.log("\nTest cases:");
testCases.forEach((testCase, index) => {
  console.log(`${index + 1}. ${testCase.description} (${testCase.name})`);
});
