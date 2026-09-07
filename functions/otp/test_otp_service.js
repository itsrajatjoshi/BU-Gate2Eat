/**
 * YummBU — OTP Service Test Runner
 * Executes both OTP Security and OTP Architecture suites.
 */

const path = require("path");
const { execSync } = require("child_process");

console.log("==================================================");
console.log("RUNNING OTP SERVICE TESTS (Architecture & Security)");
console.log("==================================================");

const rootDir = path.resolve(__dirname, "..");
try {
  execSync(`"${process.execPath}" "${path.join(rootDir, "test_otp_security.js")}"`, { stdio: "inherit" });
  execSync(`"${process.execPath}" "${path.join(rootDir, "test_otp_architecture.js")}"`, { stdio: "inherit" });
  console.log("==================================================");
  console.log("ALL OTP SERVICE TEST SUITES PASSED SUCCESSFULLY!");
  console.log("==================================================");
} catch (err) {
  process.exit(1);
}
