<?php

// autoload_static.php @generated by Composer

namespace Composer\Autoload;

class ComposerStaticInit59ce72dd28961cc3c152bd895ec00893
{
    public static $prefixLengthsPsr4 = array (
        'P' => 
        array (
            'Predis\\' => 7,
        ),
        'F' => 
        array (
            'Firebase\\JWT\\' => 13,
        ),
    );

    public static $prefixDirsPsr4 = array (
        'Predis\\' => 
        array (
            0 => __DIR__ . '/..' . '/predis/predis/src',
        ),
        'Firebase\\JWT\\' => 
        array (
            0 => __DIR__ . '/..' . '/firebase/php-jwt/src',
        ),
    );

    public static $classMap = array (
        'Composer\\InstalledVersions' => __DIR__ . '/..' . '/composer/InstalledVersions.php',
    );

    public static function getInitializer(ClassLoader $loader)
    {
        return \Closure::bind(function () use ($loader) {
            $loader->prefixLengthsPsr4 = ComposerStaticInit59ce72dd28961cc3c152bd895ec00893::$prefixLengthsPsr4;
            $loader->prefixDirsPsr4 = ComposerStaticInit59ce72dd28961cc3c152bd895ec00893::$prefixDirsPsr4;
            $loader->classMap = ComposerStaticInit59ce72dd28961cc3c152bd895ec00893::$classMap;

        }, null, ClassLoader::class);
    }
}
