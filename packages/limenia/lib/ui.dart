/// Ready-made Flutter widgets for apps that integrate Limenia: the report
/// sheet ([showLimeniaReportSheet], [LimeniaReportForm]), the complaint form
/// ([showLimeniaAppealSheet], [LimeniaAppealForm]), the statement of reasons
/// ([LimeniaStatementOfReasonsView]) and the notices for a restricted account
/// ([LimeniaRestrictionNotice], [LimeniaRestrictionScreen]).
///
/// The widgets never send anything themselves. They collect the input and
/// call the callbacks of the app, which send it with package:limenia through
/// the backend of the app. The API key of Limenia never belongs in an app.
///
/// Texts come in German and English ([LimeniaUiStrings]), colors and fonts
/// from the [Theme] of the app. See README.md.
library;

export 'src/ui/appeal.dart' show AppealTopic, LimeniaAppealForm, showLimeniaAppealSheet;
export 'src/ui/report.dart'
    show
        GoodFaithConfirmation,
        LimeniaReportForm,
        ReportCategoryOption,
        ReportDraft,
        ReportEmergencyHint,
        showLimeniaReportSheet;
export 'src/ui/restriction.dart' show LimeniaRestrictionNotice, LimeniaRestrictionScreen, LimeniaSubjectStatusBuilder;
export 'src/ui/statement_of_reasons.dart' show LimeniaStatementOfReasonsView, SorLayout;
export 'src/ui/strings.dart' show LimeniaUiStrings, LimeniaUiStringsScope, appealDeadlineFor;
