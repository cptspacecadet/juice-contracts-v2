// solidity-coverage configuration file.
//
// https://www.npmjs.com/package/solidity-coverage

module.exports = {
  skipFiles: [
    'system_tests',
    'libraries',
    'structs',
    'interfaces',
    'enums'
  ],
  configureYulOptimizer: true,
  measureStatementCoverage: false,
};
