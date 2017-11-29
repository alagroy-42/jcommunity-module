<?php
/**
* @package     jcommunity
* @author      Laurent Jouanneau
* @contributor
* @copyright   2010 Laurent Jouanneau
 * @link      http://bitbucket.org/laurentj/jcommunity
 * @license  http://www.gnu.org/licenses/lgpl.html GNU Lesser General Public Licence, see LICENCE file
*/


class jcommunityModuleInstaller extends jInstallerModule {

    protected static $key = null;

    function install() {

        if (self::$key === null) {
            self::$key = jAuth::getRandomPassword(30, true);
        }

        $authconfig = $this->config->getValue('auth','coordplugins');
        $authconfigMaster = $this->config->getValue('auth','coordplugins', null, true);
        $forWS = (in_array($this->entryPoint->type, array('json', 'jsonrpc', 'soap', 'xmlrpc')));
        $createdConfFile = false;
        if (!$authconfig || ($forWS && $authconfig == $authconfigMaster)) {
            //if ($this->entryPoint->type == 'cmdline') {
            //    return;
            //}

            if ($forWS) {
                $pluginIni = 'authsw.coord.ini.php';
            }
            else {
                $pluginIni = 'auth.coord.ini.php';
            }

            $authconfig = dirname($this->entryPoint->configFile).'/'.$pluginIni;
            if ($this->firstExec($authconfig)) {
                // no configuration, let's install the plugin for the entry point
                $this->config->setValue('auth', $authconfig, 'coordplugins');
                $this->copyFile('var/config/'.$pluginIni, 'epconfig:'.$pluginIni);
                $createdConfFile = true;
            }
        }

        $conf = new jIniFileModifier(jApp::configPath($authconfig));
        $usedStandardDao = ($conf->getValue('dao', 'Db') == 'jauthdb~jelixuser');

        $this->useDbProfile($conf->getValue('profile', 'Db'));

        $localConfigIni = $this->entryPoint->localConfigIni;
        $key = $localConfigIni->getValue('persistant_crypt_key', 'coordplugin_auth');
        if ($key === 'exampleOfCryptKey' || $key == '') {
            $localConfigIni->getMaster()->setValue('persistant_crypt_key', self::$key, 'coordplugin_auth');
        }

        if ($this->firstExec($authconfig) && $this->getParameter('rewriteconfig')) {
            $conf->setValue('driver', 'Db');
            $conf->setValue('dao','jcommunity~user', 'Db');
            $conf->setValue('form','jcommunity~account_admin', 'Db');
            $conf->setValue('error_message', 'jcommunity~login.error.notlogged');
            $conf->setValue('on_error_action', 'jcommunity~login:out');
            $conf->setValue('bad_ip_action', 'jcommunity~login:out');
            $conf->setValue('after_logout', 'jcommunity~login:index');
            $conf->setValue('enable_after_login_override', 'on');
            $conf->setValue('enable_after_logout_override', 'on');
            $conf->setValue('after_login', 'jcommunity~account:show');
            $conf->save();
        }

        if ($this->getParameter('masteradmin')) {
            $conf->setValue('after_login', 'master_admin~default:index');
            $conf->save();
            $this->config->setValue('loginResponse', 'htmlauth', 'jcommunity');
        }

        if ($this->firstDbExec() && !$this->getParameter('notjcommunitytable')) {

            $conf->setValue('dao','jcommunity~user', 'Db');
            $conf->setValue('form','jcommunity~account_admin', 'Db');
            $conf->save();

            $this->execSQLScript('sql/install');
            $cn = $this->dbConnection();
            if ($usedStandardDao && $this->getParameter('migratejauthdbusers')) {
                $cn->exec("INSERT INTO ".$cn->prefixTable('community_users')."
                            (login, password, email, nickname, status, create_date)
                         SELECT usr_login, usr_password, usr_email, usr_login, 1, '".date('Y-m-d H:i:s')."'
                         FROM ".$cn->prefixTable('jlx_user'));
            }
            else if ($this->getParameter('defaultuser')) {
                require_once(JELIX_LIB_PATH.'auth/jAuth.class.php');
                require_once(JELIX_LIB_PATH.'plugins/auth/db/db.auth.php');

                $confIni = parse_ini_file(jApp::configPath($authconfig), true);
                $authConfig = jAuth::loadConfig($confIni);
                $driver = new dbAuthDriver($authConfig['Db']);
                $passwordHash = $driver->cryptPassword('admin');
                $cn->exec("INSERT INTO ".$cn->prefixTable('community_users')." (login, password, email, nickname, status, create_date) VALUES
                            ('admin', ".$cn->quote($passwordHash).", 'admin@localhost.localdomain', 'admin', 1, '".date('Y-m-d H:i:s')."')");
            }
        }

        if ($this->firstExec('acl2') && class_exists('jAcl2DbManager')) {
            jAcl2DbManager::addSubjectGroup('jcommunity.admin', 'jcommunity~prefs.admin.jcommunity');
            jAcl2DbManager::addSubject('jcommunity.prefs.change', 'jcommunity~prefs.admin.prefs.change', 'jprefs.prefs.management');
            jAcl2DbManager::addRight('admins', 'jcommunity.prefs.change'); // for admin group
        }

        if ($this->firstExec('preferences')) {
            if (!$this->config->getValue('disableJPref', 'jcommunity')) {
                $prefIni = new jIniFileModifier(__DIR__.'/prefs.ini');
                $prefFile = jApp::configPath('preferences.ini.php');
                if (file_exists($prefFile)) {
                    $mainPref = new jIniFileModifier($prefFile);
                    //import this way to not erase changed value.
                    $prefIni->import($mainPref);
                }
                $prefIni->saveAs($prefFile);
            }
        }
    }
}