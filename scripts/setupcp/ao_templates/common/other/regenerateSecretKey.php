<?php

// https://www.mediawiki.org/wiki/Manual:Writing_maintenance_scripts

require_once(dirname(__FILE__) . "/Maintenance.php");
 
class GenerateSecretKey extends Maintenance {

   public function __construct() {
      parent::__construct();
      $this->addOption('hexlen', 'The length of the random hex.', false, true);
   }

   public function execute() {
      //echo "Hello, World!\n";
      $hex_length = $this->getOption('hexlen', 64);
      $secretKey = MWCryptRand::generateHex($hex_length, true);
      print "$secretKey";
   }

}

$maintClass = 'GenerateSecretKey';

if (defined('RUN_MAINTENANCE_IF_MAIN')) {
  require_once(RUN_MAINTENANCE_IF_MAIN);
}
else {
  require_once(DO_MAINTENANCE); # Make this work on versions before 1.17
}

