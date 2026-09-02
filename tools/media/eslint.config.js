import eslint from "@eslint/js";
import globals from "globals";

export default [
  {
    ignores: ["node_modules/"],
  },
  eslint.configs.recommended,
  {
    files: ["src/**/*.js", "test/**/*.js", "eslint.config.js"],
    languageOptions: {
      ecmaVersion: 2025,
      sourceType: "module",
      globals: globals.node,
    },
  },
];
