// --
// Copyright (C) 2001-2021 OTRS AG, https://otrs.com/
// Copyright (C) 2021 Znuny GmbH, https://znuny.org/
// --
// This software comes with ABSOLUTELY NO WARRANTY. For details, see
// the enclosed file COPYING for license information (GPL). If you
// did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
// --

"use strict";

var Core = Core || {};

/**
 * @namespace Core.Customer
 * @memberof Core
 * @author OTRS AG
 * @description
 *      This namespace contains all global functions for the customer interface.
 */
Core.Customer = (function (TargetNS) {
    if (!Core.Debug.CheckDependency('Core.Customer', 'Core.UI', 'Core.UI')) {
        return false;
    }
    if (!Core.Debug.CheckDependency('Core.Customer', 'Core.Form', 'Core.Form')) {
        return false;
    }
    if (!Core.Debug.CheckDependency('Core.Customer', 'Core.Form.Validate', 'Core.Form.Validate')) {
        return false;
    }
    if (!Core.Debug.CheckDependency('Core.Customer', 'Core.UI.Accessibility', 'Core.UI.Accessibility')) {
        return false;
    }
    if (!Core.Debug.CheckDependency('Core.Agent', 'Core.UI.InputFields', 'Core.UI.InputFields')) {
        return false;
    }

    /**
     * @name SupportedBrowser
     * @memberof Core.Customer
     * @member {Boolean}
     * @description
     *     Indicates a supported browser.
     */
    TargetNS.SupportedBrowser = true;

    /**
     * @name IECompatibilityMode
     * @memberof Core.Customer
     * @member {Boolean}
     * @description
     *     IE Compatibility Mode is active.
     */
    TargetNS.IECompatibilityMode = false;

    /**
     * @name Init
     * @memberof Core.Customer
     * @function
     * @description
     *      This function initializes the application and executes the needed functions.
     */
    TargetNS.Init = function () {
        TargetNS.SupportedBrowser = Core.App.BrowserCheck('Customer');
        TargetNS.IECompatibilityMode = Core.App.BrowserCheckIECompatibilityMode();

        if (TargetNS.IECompatibilityMode) {
            TargetNS.SupportedBrowser = false;
            Core.UI.Dialog.ShowAlert(
                Core.Language.Translate('An Error Occurred'),
                Core.Language.Translate('Please turn off Compatibility Mode in Internet Explorer!')
            );
        }

        if (!TargetNS.SupportedBrowser) {
            Core.UI.Dialog.ShowAlert(
                Core.Language.Translate('An Error Occurred'),
                Core.Language.Translate('The browser you are using is too old.')
                + ' '
                + Core.Language.Translate('This software runs with a huge lists of browsers, please upgrade to one of these.')
                + ' '
                + Core.Language.Translate('Please see the documentation or ask your admin for further information.')
            );
        }

        // check if we're on a touch device and on the regular resolution (non-mobile). If that's the case,
        // don't allow triggering the link on "parent" elements directly, they should only expand the sub menu
        Core.App.Responsive.CheckIfTouchDevice();
        $('#Navigation > ul > li > a').on('click', function(Event) {
            if (Core.App.Responsive.IsTouchDevice() && $(this).next('ul:visible').length && Core.App.Responsive.GetScreenSize() === 'ScreenXL') {
                Event.preventDefault();
                Event.stopPropagation();
            }
        });

        // unveil full error details only on click
        $('.TriggerFullErrorDetails').on('click', function() {
            $('.Content.ErrorDetails').toggle();
        });

        InitAvatarFlyout();

    };

    /**
     * @name ClickableRow
     * @memberof Core.Customer
     * @function
     * @description
     *      This function makes the whole row in the MyTickets and CompanyTickets view clickable.
     */
    TargetNS.ClickableRow = function(){
        $("table tr").click(function(){
            window.location.href = $("a", this).attr("href");
            return false;
        });
    };

    /**
     * @name Enhance
     * @memberof Core.Customer
     * @function
     * @description
     *      This function adds the class 'JavaScriptAvailable' to the 'Body' div to enhance the interface (clickable rows).
     */
    TargetNS.Enhance = function(){
        $('body').removeClass('NoJavaScript').addClass('JavaScriptAvailable');
    };

    /**
     * @private
     * @name InitAvatarFlyout
     * @memberof Core.Agent
     * @function
     * @description
     *      This function initializes the flyout when the avatar on the top left is clicked.
     */
    function InitAvatarFlyout() {

        var Timeout = {},
            ID,
            TimeoutDuration = 700;

        $.each($('#HeaderToolBar > li'), function () {

            ID = $(this).attr('id');

            // init the HeaderToolBar li toggle
            $(this).find('a').off('click.HeaderToolBar').on('click.HeaderToolBar', function() {
                $(this).next('div').fadeToggle('fast');
                $(this).toggleClass('Active');
            });

            $(this).find('div').first().off('mouseenter.HeaderToolBar').on('mouseenter.HeaderToolBar', function() {
                if (Timeout[ID] && $(this).css('opacity') == 1) {
                    clearTimeout(Timeout[ID]);
                }
            });

            $(this).find('div').first().off('mouseleave.HeaderToolBar').on('mouseleave.HeaderToolBar', function() {
                var $Content = $(this);
                Timeout[ID] = setTimeout(function() {
                    $Content.fadeOut('fast');
                    $Content.prev('a').removeClass('Active');
                }, TimeoutDuration);
            });
        })
    }

    Core.Init.RegisterNamespace(TargetNS, 'APP_GLOBAL_EARLY');

    return TargetNS;
}(Core.Customer || {}));
