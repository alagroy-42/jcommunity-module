<?php
/* comments & extra-whitespaces have been removed by jBuildTools*/
/**
* @package     jelix
* @subpackage  core_request
* @author      Laurent Jouanneau
* @contributor Loic Mathaud
* @contributor Thibault PIRONT < nuKs >
* @contributor Thiriot Christophe
* @copyright   2005-2008 Laurent Jouanneau, 2006-2007 Loic Mathaud
* @copyright   2007 Thibault PIRONT
* @copyright   2008 Thiriot Christophe
* @link        http://www.jelix.org
* @licence     GNU Lesser General Public Licence see LICENCE file or http://www.gnu.org/licenses/lgpl.html
*/
class jCmdLineRequest extends jRequest{
	public $type = 'cmdline';
	public $defaultResponseType = 'cmdline';
	public function isAllowedResponse($respclass){
		return('jResponseCmdline' == $respclass);
	}
	protected function _initUrlData(){
		global $gJConfig;
		$this->urlScriptPath = '/';
		$this->urlScriptName = $this->urlScript = $_SERVER['SCRIPT_NAME'];
		$this->urlPathInfo = '';
	}
	protected function _initParams(){
		global $gJConfig;
		$argv = $_SERVER['argv'];
		$scriptName = array_shift($argv);
		if($_SERVER['argc'] == 1){
			$argsel = $gJConfig->startModule.'~'.$gJConfig->startAction;
		} else{
			$argsel = array_shift($argv);
			if($argsel == 'help'){
				$argsel = 'jelix~help:index';
			}
			if(!preg_match('/(?:([\w\.]+)~)/', $argsel)){
				$argsel = $gJConfig->startModule.'~'.$argsel;
			}
		}
		$selector = new jSelectorAct($argsel);
		$this->params = $argv;
		$this->params['module'] = $selector->module;
		$this->params['action'] = $selector->resource;
	}
}