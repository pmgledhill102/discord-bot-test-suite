<?php

/**
 * OPcache Preload Script
 *
 * Preloads commonly used classes to improve cold start performance.
 * This script runs once when PHP starts and keeps classes in shared memory.
 */

require_once __DIR__.'/vendor/autoload.php';

// Preload Laravel core classes
$laravelClasses = [
    \Illuminate\Foundation\Application::class,
    \Illuminate\Http\Request::class,
    \Illuminate\Http\Response::class,
    \Illuminate\Http\JsonResponse::class,
    \Illuminate\Routing\Router::class,
    \Illuminate\Routing\Route::class,
    \Illuminate\Routing\Controller::class,
    \Illuminate\Support\Facades\Route::class,
    \Illuminate\Support\ServiceProvider::class,
    \Illuminate\Foundation\Http\Kernel::class,
    \Illuminate\Contracts\Http\Kernel::class,
];

// Preload application classes
$appClasses = [
    \App\Http\Controllers\InteractionController::class,
    \App\Http\Middleware\VerifyDiscordSignature::class,
    \App\Services\PubSubPublisher::class,
    \App\Providers\AppServiceProvider::class,
];

foreach (array_merge($laravelClasses, $appClasses) as $class) {
    if (class_exists($class) || interface_exists($class)) {
        // Class is now loaded and will be kept in OPcache
    }
}
