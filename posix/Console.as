// Copyright (c) 2013 Adobe Systems Inc

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

package com.adobe.flascc {
import com.adobe.flascc.vfs.ISpecialFile;

import flash.display.DisplayObjectContainer;
import flash.display.Sprite;
import flash.display.StageScaleMode;
import flash.events.Event;
import flash.text.TextField;

/**
 * A basic implementation of a console for CrossBridge apps.
 * The PlayerKernel class delegates to this for things like read/write,
 * so that console output can be displayed in a TextField on the Stage.
 */
public class Console extends Sprite implements ISpecialFile {

    /**
     * @private
     */
    private var enableConsole:Boolean;

    /**
     * @private
     */
    private var _tf:TextField;

    /**
     * @private
     */
    private var inputContainer:DisplayObjectContainer;

    /**
     * To Support the preloader case you might want to have the Console
     * act as a child of some other DisplayObjectContainer.
     */
    public function Console(container:DisplayObjectContainer = null, enableConsole:Boolean = true) {
        CONFIG::debug {
            trace("Console::created");
        }

        CModule.rootSprite = container ? container.root : this;
        this.enableConsole = enableConsole;

        if (CModule.runningAsWorker()) {
            return;
        }

        if (container) {
            container.addChild(this);
            init(null);
        } else {
            addEventListener(Event.ADDED_TO_STAGE, init, false, 0, true);
        }
    }

    /**
     * All of the real FlasCC init happens in this method,
     * which is either run on startup or once the SWF has
     * been added to the stage.
     */
    protected function init(event:Event):void {
        CONFIG::debug {
            trace("Console::init");
        }
        // setup stage properties
        stage.frameRate = 60;
        stage.scaleMode = StageScaleMode.NO_SCALE;
        // create input container
        inputContainer = new Sprite();
        addChild(inputContainer);
        // create console
        if (enableConsole) {
            _tf = new TextField();
            _tf.multiline = true;
            _tf.width = stage.stageWidth;
            _tf.height = stage.stageHeight;
            inputContainer.addChild(_tf);
        }

        try {
            // change to false to prevent running main in the background
            // when Workers are supported
            const runMainBg:Boolean = true;

            // PlayerKernel will delegate read/write requests to the "/dev/tty"
            // file to the object specified with this API.
            CModule.vfs.console = this;

            // By default we run "main" on a background worker so that
            // console updates show up in real time. Otherwise "startAsync"
            // causes main to run on the UI worker
            if (runMainBg && CModule.canUseWorkers) // start in bg if we have workers
                CModule.startBackground(this, new <String>[], new <String>[]);
            else
                CModule.startAsync(this);
        }
        catch (error:*) {
            // If main gives any exceptions make sure we get a full stack trace
            // in our console
            consoleWrite(error.toString() + "\n" + error.getStackTrace().toString());
            throw error;
        }
        // remove event listener
        removeEventListener(Event.ADDED_TO_STAGE, init);
        // attach event listeners
        addEventListener(Event.ENTER_FRAME, CModule.serviceUIRequests, false, 0, true);
        addEventListener(Event.REMOVED_FROM_STAGE, dispose, false, 0, true);
    }

    /**
     * Disposes Console freeing memory
     */
    public function dispose(event:Event = null):void {
        removeEventListener(Event.ADDED_TO_STAGE, init);
        removeEventListener(Event.REMOVED_FROM_STAGE, dispose);
        removeEventListener(Event.ENTER_FRAME, CModule.serviceUIRequests);
        inputContainer = null;
        _tf = null;
    }

    /**
     * Switches default console logging behaviour (text field output)
     */
    public function switchConsole(isEnabled:Boolean):void {
        enableConsole = isEnabled;
    }

    /**
     * The callback to call when CrossBridge code calls the <code>posix exit()</code> function. Leave null to exit silently.
     * @private
     */
    public var exitHook:Function;

    /**
     * The PlayerKernel implementation will use this function to handle
     * C process exit requests
     */
    public function exit(code:int):Boolean {
        CONFIG::debug {
            trace("Console::exit: " + code);
        }
        // default to unhandled
        if (exitHook != null)
            return exitHook(code);
        else
            throw new Error("exit() called.");
    }

    /**
     * The PlayerKernel implementation uses this function to handle
     * C IO write requests to the file "/dev/tty" (for example, output from
     * printf will pass through this function). See the ISpecialFile
     * documentation for more information about the arguments and return value.
     */
    public function write(fd:int, bufPtr:int, nbyte:int, errnoPtr:int):int {
        var str:String = CModule.readString(bufPtr, nbyte);
        consoleWrite(str);
        return nbyte;
    }

    /**
     * The PlayerKernel implementation uses this function to handle
     * C IO read requests to the file "/dev/tty" (for example, reads from stdin
     * will expect this function to provide the data). See the ISpecialFile
     * documentation for more information about the arguments and return value.
     */
    public function read(fd:int, bufPtr:int, nbyte:int, errnoPtr:int):int {
        return 0;
    }

    /**
     * The PlayerKernel implementation uses this function to handle
     * C fcntl requests to the file "/dev/tty."
     * See the ISpecialFile documentation for more information about the
     * arguments and return value.
     */
    public function fcntl(fd:int, com:int, data:int, errnoPtr:int):int {
        return 0;
    }

    /**
     * The PlayerKernel implementation uses this function to handle
     * C ioctl requests to the file "/dev/tty."
     * See the ISpecialFile documentation for more information about the
     * arguments and return value.
     */
    public function ioctl(fd:int, com:int, data:int, errnoPtr:int):int {
        return CModule.callI(CModule.getPublicSymbol("vglttyioctl"), new <int>[fd, com, data, errnoPtr]);
    }

    /**
     * Helper function that traces to the flashlog text file and also
     * displays output in the on-screen textfield console.
     */
    protected function consoleWrite(s:String):void {
        trace(s);
        if (enableConsole) {
            _tf.appendText(s);
            _tf.scrollV = _tf.maxScrollV;
        }
    }

    /**
     * The enterFrame callback is run once every frame. UI thunk requests should be handled
     * here by calling <code>CModule.serviceUIRequests()</code> (see CModule ASdocs for more information on the UI thunking functionality).
     */
    protected function enterFrame(e:Event):void {
        throw new Error("Deprecated, you should attach your listener directly into CModule.serviceUIRequests() or make your own handler.");
        //CModule.serviceUIRequests();
    }

    /**
     * Provide a way to get the TextField's text.
     */
    public function get consoleText():String {
        var result:String = null;
        if (_tf != null) {
            result = _tf.text;
        }
        return result;
    }
}
}
