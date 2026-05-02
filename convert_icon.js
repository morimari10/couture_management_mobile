const sharp = require("sharp");
const fs = require("fs");
const path = require("path");

const svgPath = path.join(__dirname, "assets", "images", "logo.svg");
const svgContent = fs.readFileSync(svgPath);

// Output a 1024x1024 PNG for the app icon
sharp(svgContent)
  .resize(1024, 1024, { fit: "contain", background: { r: 255, g: 248, b: 246, alpha: 1 } })
  .png()
  .toFile(path.join(__dirname, "assets", "images", "icon.png"))
  .then(() => {
    console.log("Created icon.png (1024x1024)");
    // Also create a 512x512 for general use in-app
    return sharp(svgContent)
      .resize(512, 512, { fit: "contain", background: { r: 255, g: 248, b: 246, alpha: 1 } })
      .png()
      .toFile(path.join(__dirname, "assets", "images", "logo.png"));
  })
  .then(() => console.log("Created logo.png (512x512)"))
  .catch(e => console.error("Error:", e.message));
