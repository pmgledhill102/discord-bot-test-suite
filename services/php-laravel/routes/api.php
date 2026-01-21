<?php

use App\Http\Controllers\InteractionController;
use Illuminate\Support\Facades\Route;

Route::post('/', [InteractionController::class, 'handle']);
Route::post('/interactions', [InteractionController::class, 'handle']);
